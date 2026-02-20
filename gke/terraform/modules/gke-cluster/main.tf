# ============================================================
# Module: gke-cluster
# Creates a private, regional GKE cluster with enterprise
# security defaults: Workload Identity, etcd encryption,
# Binary Authorization, Shielded Nodes, Dataplane V2.
# ============================================================

locals {
  master_auth_networks = [
    for cidr in var.master_authorized_networks : {
      display_name = cidr
      cidr_block   = cidr
    }
  ]
}

# ─────────────────────────────────────────────
# Enable required APIs
# ─────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "containeranalysis.googleapis.com",
    "binaryauthorization.googleapis.com",
    "cloudkms.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "stackdriver.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "anthos.googleapis.com",
    "gkeconnect.googleapis.com",
    "gkehub.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ─────────────────────────────────────────────
# KMS Key Ring & Key for etcd encryption
# ─────────────────────────────────────────────
resource "google_kms_key_ring" "gke" {
  project  = var.project_id
  name     = "${var.cluster_name}-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "etcd" {
  name            = "${var.cluster_name}-etcd-key"
  key_ring        = google_kms_key_ring.gke.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

# Grant GKE service account access to KMS key
resource "google_kms_crypto_key_iam_member" "gke_sa_kms" {
  crypto_key_id = google_kms_crypto_key.etcd.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@container-engine-robot.iam.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.project_id
}

# ─────────────────────────────────────────────
# GKE Cluster Service Account (least privilege)
# ─────────────────────────────────────────────
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes-sa"
  display_name = "GKE Node Service Account for ${var.cluster_name}"
}

# Minimal permissions for nodes (not the default editor role)
resource "google_project_iam_member" "node_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ─────────────────────────────────────────────
# Binary Authorization Policy
# ─────────────────────────────────────────────
resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = var.binary_auth_enforcement_mode

    require_attestations_by = [
      google_binary_authorization_attestor.build_verified.name,
    ]
  }

  # Allow GKE system images without attestation
  cluster_admission_rules {
    cluster                 = "${var.region}.${var.cluster_name}"
    evaluation_mode         = "ALWAYS_ALLOW"
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }
}

resource "google_binary_authorization_attestor" "build_verified" {
  project = var.project_id
  name    = "${var.cluster_name}-build-verified"

  attestation_authority_note {
    note_reference = google_container_analysis_note.build_note.name

    public_keys {
      id = data.google_kms_crypto_key_version.attestor_key_version.id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.attestor_key_version.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.attestor_key_version.public_key[0].algorithm
      }
    }
  }
}

resource "google_container_analysis_note" "build_note" {
  project = var.project_id
  name    = "${var.cluster_name}-build-note"

  attestation_authority {
    hint {
      human_readable_name = "Build Verified Attestor"
    }
  }
}

resource "google_kms_crypto_key" "attestor_key" {
  name     = "${var.cluster_name}-attestor-key"
  key_ring = google_kms_key_ring.gke.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm = "RSA_SIGN_PKCS1_4096_SHA512"
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "google_kms_crypto_key_version" "attestor_key_version" {
  crypto_key = google_kms_crypto_key.attestor_key.id
}

# ─────────────────────────────────────────────
# GKE Cluster
# ─────────────────────────────────────────────
resource "google_container_cluster" "cluster" {
  provider = google-beta

  project  = var.project_id
  name     = var.cluster_name
  location = var.region # Regional cluster (multi-zone)

  # Use a separately managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnetwork_id

  # ── Networking ──────────────────────────────
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Private cluster - no public node IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Keep public endpoint, restrict via authorized networks
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Restrict API server access
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = local.master_auth_networks
      content {
        display_name = cidr_blocks.value.display_name
        cidr_block   = cidr_blocks.value.cidr_block
      }
    }
  }

  # ── Dataplane V2 (eBPF / Cilium) ────────────
  datapath_provider = "ADVANCED_DATAPATH"

  # ── Security ─────────────────────────────────
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.etcd.id
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # ── Shielded Nodes ───────────────────────────
  enable_shielded_nodes = true

  # ── Add-ons ──────────────────────────────────
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    gcp_filestore_csi_driver_config {
      enabled = true
    }
  }

  # ── Network Policy ───────────────────────────
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # ── Monitoring & Logging ─────────────────────
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE", "HPA", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET"]

    managed_prometheus {
      enabled = true
    }
  }

  # ── Release Channel ───────────────────────────
  release_channel {
    channel = var.release_channel
  }

  # ── Maintenance Window ────────────────────────
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # ── Cluster Autoscaling ────────────────────────
  cluster_autoscaling {
    enabled             = var.enable_node_auto_provisioning
    autoscaling_profile = "OPTIMIZE_UTILIZATION"

    dynamic "resource_limits" {
      for_each = var.enable_node_auto_provisioning ? [1] : []
      content {
        resource_type = "cpu"
        minimum       = 4
        maximum       = 256
      }
    }

    dynamic "resource_limits" {
      for_each = var.enable_node_auto_provisioning ? [1] : []
      content {
        resource_type = "memory"
        minimum       = 16
        maximum       = 1024
      }
    }
  }

  # ── Notifications ─────────────────────────────
  notification_config {
    pubsub {
      enabled = true
      topic   = google_pubsub_topic.cluster_notifications.id
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_kms_crypto_key_iam_member.gke_sa_kms,
  ]
}

# ─────────────────────────────────────────────
# Pub/Sub for cluster notifications
# ─────────────────────────────────────────────
resource "google_pubsub_topic" "cluster_notifications" {
  project = var.project_id
  name    = "${var.cluster_name}-notifications"
}
