# ============================================================
# Module: gke-node-pool
# Creates a GKE node pool with enterprise security defaults.
# Supports standard and spot node pools with autoscaling.
# ============================================================

resource "google_container_node_pool" "pool" {
  provider = google-beta

  project    = var.project_id
  name       = var.pool_name
  cluster    = var.cluster_id
  location   = var.region
  node_count = null # Managed by autoscaler

  # ── Autoscaling ───────────────────────────────
  autoscaling {
    min_node_count  = var.min_node_count
    max_node_count  = var.max_node_count
    location_policy = "BALANCED" # Spread across zones evenly
  }

  # ── Management ────────────────────────────────
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # ── Upgrade Settings ──────────────────────────
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  # ── Node Config ───────────────────────────────
  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    image_type   = "COS_CONTAINERD" # Container-Optimized OS

    spot = var.use_spot_instances

    service_account = var.node_service_account_email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # ── Workload Identity ────────────────────────
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # ── Shielded VM ──────────────────────────────
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # ── Labels & Taints ──────────────────────────
    labels = merge(
      {
        "pool"        = var.pool_name
        "environment" = var.environment
        "managed-by"  = "terraform"
      },
      var.extra_labels
    )

    dynamic "taint" {
      for_each = var.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Node tags for firewall rules
    tags = concat(["gke-node", "gke-${var.pool_name}"], var.extra_tags)

    # ── Metadata ─────────────────────────────────
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # ── Resource Manager Tags ─────────────────────
    resource_labels = {
      "pool"        = var.pool_name
      "environment" = var.environment
      "cost-center" = var.cost_center
    }

    # ── Linux Node Config ─────────────────────────
    linux_node_config {
      sysctls = {
        "net.core.somaxconn"         = "32768"
        "net.ipv4.tcp_max_syn_backlog" = "8096"
      }
    }

    # ── Local SSD / ephemeral storage (optional) ──
    dynamic "ephemeral_storage_local_ssd_config" {
      for_each = var.local_ssd_count > 0 ? [1] : []
      content {
        local_ssd_count = var.local_ssd_count
      }
    }
  }

  lifecycle {
    create_before_destroy = true

    ignore_changes = [
      node_config[0].resource_labels,
    ]
  }
}
