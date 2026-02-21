# ============================================================
# Module: artifact-registry
# Creates an Artifact Registry repository for container images
# and Helm charts with vulnerability scanning and CMEK.
# ============================================================

resource "google_project_service" "artifact_registry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container_analysis" {
  project            = var.project_id
  service            = "containeranalysis.googleapis.com"
  disable_on_destroy = false
}

# ─────────────────────────────────────────────
# KMS Key for repository encryption
# ─────────────────────────────────────────────
resource "google_kms_key_ring" "registry" {
  project  = var.project_id
  name     = "${var.prefix}-registry-keyring"
  location = var.location
}

resource "google_kms_crypto_key" "registry" {
  name            = "${var.prefix}-registry-key"
  key_ring        = google_kms_key_ring.registry.id
  rotation_period = "7776000s"
}

# Grant Artifact Registry SA access to KMS
resource "google_kms_crypto_key_iam_member" "registry_kms" {
  crypto_key_id = google_kms_crypto_key.registry.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.project_id
}

# ─────────────────────────────────────────────
# Container Image Repository
# ─────────────────────────────────────────────
resource "google_artifact_registry_repository" "containers" {
  project       = var.project_id
  location      = var.location
  repository_id = "${var.prefix}-containers"
  description   = "Container images for ${var.prefix}"
  format        = "DOCKER"

  kms_key_name = google_kms_crypto_key.registry.id

  cleanup_policies {
    id     = "keep-tagged-releases"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["v", "release-"]
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }

  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [
    google_project_service.artifact_registry,
    google_kms_crypto_key_iam_member.registry_kms,
  ]
}

# ─────────────────────────────────────────────
# Helm Chart Repository
# ─────────────────────────────────────────────
resource "google_artifact_registry_repository" "helm" {
  project       = var.project_id
  location      = var.location
  repository_id = "${var.prefix}-helm-charts"
  description   = "Helm charts for ${var.prefix}"
  format        = "HELM"

  kms_key_name = google_kms_crypto_key.registry.id

  depends_on = [
    google_project_service.artifact_registry,
    google_kms_crypto_key_iam_member.registry_kms,
  ]
}

# ─────────────────────────────────────────────
# IAM – Read access for GKE node pools
# ─────────────────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "gke_readers" {
  for_each = toset(var.reader_service_accounts)

  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.containers.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value}"
}

# ─────────────────────────────────────────────
# IAM – Write access for CI/CD pipelines
# ─────────────────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "ci_writers" {
  for_each = toset(var.writer_service_accounts)

  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.containers.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${each.value}"
}
