# ============================================================
# Environment: Production
# Orchestrates all modules to build the full enterprise
# GKE platform in the production environment.
# ============================================================

terraform {
  backend "gcs" {
    bucket = "myorg-terraform-state-prod"
    prefix = "terraform/prod"
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

# Kubernetes provider – populated after cluster creation
provider "kubernetes" {
  host                   = "https://${module.gke_primary.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.gke_primary.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke_primary.cluster_endpoint}"
    cluster_ca_certificate = base64decode(module.gke_primary.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

data "google_client_config" "default" {}

# ─────────────────────────────────────────────
# 1. Shared VPC & Networking
# ─────────────────────────────────────────────
module "shared_vpc" {
  source = "../../modules/shared-vpc"

  prefix          = local.prefix
  host_project_id = var.host_project_id
  service_project_ids = [
    var.cluster_project_id,
    var.shared_services_project_id,
  ]

  regions = {
    primary = var.primary_region
    dr      = var.dr_region
  }

  subnets = {
    "gke-prod-primary" = {
      region        = var.primary_region
      ip_cidr_range = "10.0.0.0/20"
      pods_cidr     = "10.4.0.0/14"
      services_cidr = "10.0.16.0/20"
    }
    "gke-prod-dr" = {
      region        = var.dr_region
      ip_cidr_range = "10.1.0.0/20"
      pods_cidr     = "10.8.0.0/14"
      services_cidr = "10.1.16.0/20"
    }
  }

  master_ipv4_cidrs = [
    var.primary_master_cidr,
    var.dr_master_cidr,
  ]

  internal_domain = var.internal_domain
}

# ─────────────────────────────────────────────
# 2. Artifact Registry (Shared Services)
# ─────────────────────────────────────────────
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = var.shared_services_project_id
  prefix     = local.prefix
  location   = var.primary_region

  reader_service_accounts = [
    module.gke_primary.node_service_account_email,
    module.gke_dr.node_service_account_email,
  ]

  writer_service_accounts = [
    "serviceAccount:${var.cicd_service_account_email}",
  ]

  depends_on = [module.gke_primary, module.gke_dr]
}

# ─────────────────────────────────────────────
# 3. Security (WAF, Org Policies, Secrets)
# ─────────────────────────────────────────────
module "security" {
  source = "../../modules/security"

  project_id     = var.cluster_project_id
  prefix         = local.prefix
  environment    = "prod"
  primary_region = var.primary_region
  dr_region      = var.dr_region
  org_id         = var.org_id

  allowed_ip_ranges = var.allowed_ip_ranges

  secret_ids = [
    "argocd-admin-password",
    "grafana-admin-password",
    "alertmanager-slack-webhook",
  ]
}

# ─────────────────────────────────────────────
# 4a. Primary GKE Cluster (europe-west1)
# ─────────────────────────────────────────────
module "gke_primary" {
  source = "../../modules/gke-cluster"

  project_id   = var.cluster_project_id
  cluster_name = "${local.prefix}-primary"
  region       = var.primary_region

  network_id    = module.shared_vpc.network_id
  subnetwork_id = module.shared_vpc.subnet_ids["gke-prod-primary"]

  pods_range_name     = module.shared_vpc.pods_range_names["gke-prod-primary"]
  services_range_name = module.shared_vpc.services_range_names["gke-prod-primary"]

  master_ipv4_cidr_block     = var.primary_master_cidr
  master_authorized_networks = var.master_authorized_networks
  release_channel            = "REGULAR"

  binary_auth_enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  enable_node_auto_provisioning = false

  depends_on = [module.shared_vpc]
}

# ─────────────────────────────────────────────
# 4b. DR GKE Cluster (us-central1)
# ─────────────────────────────────────────────
module "gke_dr" {
  source = "../../modules/gke-cluster"

  project_id   = var.cluster_project_id
  cluster_name = "${local.prefix}-dr"
  region       = var.dr_region

  network_id    = module.shared_vpc.network_id
  subnetwork_id = module.shared_vpc.subnet_ids["gke-prod-dr"]

  pods_range_name     = module.shared_vpc.pods_range_names["gke-prod-dr"]
  services_range_name = module.shared_vpc.services_range_names["gke-prod-dr"]

  master_ipv4_cidr_block     = var.dr_master_cidr
  master_authorized_networks = var.master_authorized_networks
  release_channel            = "REGULAR"

  binary_auth_enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  enable_node_auto_provisioning = false

  depends_on = [module.shared_vpc]
}

# ─────────────────────────────────────────────
# 5. Node Pools – Primary Cluster
# ─────────────────────────────────────────────

# System pool (platform components: ArgoCD, monitoring, service mesh)
module "node_pool_system" {
  source = "../../modules/gke-node-pool"

  project_id                 = var.cluster_project_id
  cluster_id                 = module.gke_primary.cluster_id
  pool_name                  = "system-pool"
  region                     = var.primary_region
  environment                = "prod"
  cost_center                = "platform"
  node_service_account_email = module.gke_primary.node_service_account_email

  machine_type   = "n2-standard-4"
  disk_size_gb   = 100
  disk_type      = "pd-ssd"
  min_node_count = 1
  max_node_count = 3
  use_spot_instances = false

  taints = [
    {
      key    = "dedicated"
      value  = "system"
      effect = "NO_SCHEDULE"
    }
  ]

  extra_labels = {
    "pool-type" = "system"
  }
}

# General pool (standard application workloads)
module "node_pool_general" {
  source = "../../modules/gke-node-pool"

  project_id                 = var.cluster_project_id
  cluster_id                 = module.gke_primary.cluster_id
  pool_name                  = "general-pool"
  region                     = var.primary_region
  environment                = "prod"
  cost_center                = "shared"
  node_service_account_email = module.gke_primary.node_service_account_email

  machine_type   = "n2-standard-8"
  disk_size_gb   = 100
  disk_type      = "pd-balanced"
  min_node_count = 1
  max_node_count = 20
  use_spot_instances = false

  extra_labels = {
    "pool-type" = "general"
  }
}

# Spot pool (batch jobs, stateless workloads)
module "node_pool_spot" {
  source = "../../modules/gke-node-pool"

  project_id                 = var.cluster_project_id
  cluster_id                 = module.gke_primary.cluster_id
  pool_name                  = "spot-pool"
  region                     = var.primary_region
  environment                = "prod"
  cost_center                = "shared"
  node_service_account_email = module.gke_primary.node_service_account_email

  machine_type   = "n2-standard-8"
  disk_size_gb   = 100
  disk_type      = "pd-balanced"
  min_node_count = 0
  max_node_count = 50
  use_spot_instances = true

  taints = [
    {
      key    = "cloud.google.com/gke-spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  ]

  extra_labels = {
    "pool-type" = "spot"
  }
}

# Memory-optimized pool (ML inference, data workloads)
module "node_pool_memory" {
  source = "../../modules/gke-node-pool"

  project_id                 = var.cluster_project_id
  cluster_id                 = module.gke_primary.cluster_id
  pool_name                  = "memory-pool"
  region                     = var.primary_region
  environment                = "prod"
  cost_center                = "data"
  node_service_account_email = module.gke_primary.node_service_account_email

  machine_type   = "n2-highmem-16"
  disk_size_gb   = 200
  disk_type      = "pd-ssd"
  min_node_count = 0
  max_node_count = 10
  use_spot_instances = false

  taints = [
    {
      key    = "dedicated"
      value  = "memory-optimized"
      effect = "NO_SCHEDULE"
    }
  ]

  extra_labels = {
    "pool-type" = "memory-optimized"
  }
}

# ─────────────────────────────────────────────
# 6. Team Namespaces (multi-tenancy)
# ─────────────────────────────────────────────
module "team_payments" {
  source = "../../modules/team-namespace"

  project_id  = var.cluster_project_id
  namespace   = "team-payments"
  team_name   = "payments"
  environment = "prod"
  cost_center = "payments-biz-unit"

  quota = {
    requests_cpu    = "20"
    requests_memory = "40Gi"
    limits_cpu      = "40"
    limits_memory   = "80Gi"
    max_pods        = "100"
    max_services    = "30"
    max_secrets     = "100"
    max_configmaps  = "100"
    max_pvcs        = "20"
    max_storage     = "1Ti"
  }

  admin_groups     = ["payments-leads@example.com"]
  developer_groups = ["payments-devs@example.com"]

  gcp_roles = [
    "roles/secretmanager.secretAccessor",
    "roles/cloudtrace.agent",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [module.gke_primary]
}

module "team_identity" {
  source = "../../modules/team-namespace"

  project_id  = var.cluster_project_id
  namespace   = "team-identity"
  team_name   = "identity"
  environment = "prod"
  cost_center = "identity-biz-unit"

  admin_groups     = ["identity-leads@example.com"]
  developer_groups = ["identity-devs@example.com"]

  gcp_roles = [
    "roles/secretmanager.secretAccessor",
    "roles/cloudtrace.agent",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [module.gke_primary]
}

module "team_data" {
  source = "../../modules/team-namespace"

  project_id  = var.cluster_project_id
  namespace   = "team-data"
  team_name   = "data"
  environment = "prod"
  cost_center = "data-biz-unit"

  quota = {
    requests_cpu    = "40"
    requests_memory = "80Gi"
    limits_cpu      = "80"
    limits_memory   = "160Gi"
    max_pods        = "200"
    max_services    = "50"
    max_secrets     = "100"
    max_configmaps  = "100"
    max_pvcs        = "50"
    max_storage     = "5Ti"
  }

  admin_groups     = ["data-leads@example.com"]
  developer_groups = ["data-devs@example.com"]

  gcp_roles = [
    "roles/secretmanager.secretAccessor",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/cloudtrace.agent",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [module.gke_primary]
}

# ─────────────────────────────────────────────
# 7. Platform Helm Releases
# ─────────────────────────────────────────────

# ArgoCD (GitOps engine)
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "6.7.0"
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/helm-values/argocd.yaml")]

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.argocd_admin_password
  }

  depends_on = [module.node_pool_system]
}

# cert-manager (TLS certificate automation)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.14.0"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  depends_on = [module.node_pool_system]
}

# External Secrets Operator (Secret Manager integration)
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.13"
  namespace        = "external-secrets"
  create_namespace = true

  depends_on = [module.node_pool_system]
}

# Metrics Server (required for HPA)
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.0"
  namespace        = "kube-system"

  depends_on = [module.node_pool_system]
}

# Vertical Pod Autoscaler
resource "helm_release" "vpa" {
  name             = "vpa"
  repository       = "https://charts.fairwinds.com/stable"
  chart            = "vpa"
  version          = "3.0.2"
  namespace        = "vpa"
  create_namespace = true

  depends_on = [module.node_pool_system]
}

# ─────────────────────────────────────────────
# 8. Locals
# ─────────────────────────────────────────────
locals {
  prefix = "${var.org_name}-prod"
}
