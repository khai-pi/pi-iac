# ============================================================
# Environment: Dev
# Lighter-weight cluster for development teams.
# Single region, relaxed security policies, smaller nodes.
# ============================================================

terraform {
  backend "gcs" {
    bucket = "myorg-terraform-state-dev"
    prefix = "terraform/dev"
  }
}

provider "google" {
  project = var.cluster_project_id
  region  = var.primary_region
}

provider "google-beta" {
  project = var.cluster_project_id
  region  = var.primary_region
}

provider "kubernetes" {
  host                   = "https://${module.gke_dev.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.gke_dev.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

data "google_client_config" "default" {}

locals {
  prefix = "${var.org_name}-dev"
}

# ─────────────────────────────────────────────
# Networking (simpler – single region)
# ─────────────────────────────────────────────
module "shared_vpc" {
  source = "../../modules/shared-vpc"

  prefix          = local.prefix
  host_project_id = var.host_project_id
  service_project_ids = [var.cluster_project_id]

  regions = {
    primary = var.primary_region
  }

  subnets = {
    "gke-dev-primary" = {
      region        = var.primary_region
      ip_cidr_range = "10.2.0.0/20"
      pods_cidr     = "10.12.0.0/14"
      services_cidr = "10.2.16.0/20"
    }
  }

  master_ipv4_cidrs = [var.primary_master_cidr]
  internal_domain   = var.internal_domain
}

# ─────────────────────────────────────────────
# GKE Dev Cluster
# ─────────────────────────────────────────────
module "gke_dev" {
  source = "../../modules/gke-cluster"

  project_id   = var.cluster_project_id
  cluster_name = "${local.prefix}-cluster"
  region       = var.primary_region

  network_id    = module.shared_vpc.network_id
  subnetwork_id = module.shared_vpc.subnet_ids["gke-dev-primary"]

  pods_range_name     = module.shared_vpc.pods_range_names["gke-dev-primary"]
  services_range_name = module.shared_vpc.services_range_names["gke-dev-primary"]

  master_ipv4_cidr_block     = var.primary_master_cidr
  master_authorized_networks = var.master_authorized_networks
  release_channel            = "RAPID" # Latest features for dev

  # Audit-only in dev (don't block deployments)
  binary_auth_enforcement_mode = "DRYRUN_AUDIT_LOG_ONLY"
  enable_node_auto_provisioning = true

  depends_on = [module.shared_vpc]
}

# ─────────────────────────────────────────────
# Node Pools – Dev (smaller, mostly spot)
# ─────────────────────────────────────────────
module "node_pool_general" {
  source = "../../modules/gke-node-pool"

  project_id                 = var.cluster_project_id
  cluster_id                 = module.gke_dev.cluster_id
  pool_name                  = "general-pool"
  region                     = var.primary_region
  environment                = "dev"
  cost_center                = "platform-dev"
  node_service_account_email = module.gke_dev.node_service_account_email

  machine_type       = "n2-standard-4"
  disk_size_gb       = 50
  disk_type          = "pd-balanced"
  min_node_count     = 0 # Scale to zero in dev
  max_node_count     = 10
  use_spot_instances = true # Spot instances for cost savings in dev
}
