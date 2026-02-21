# ============================================================
# Module: team-namespace
# Onboards an application team: namespace, ResourceQuota,
# LimitRange, NetworkPolicy, RBAC, Workload Identity binding.
# ============================================================

# ─────────────────────────────────────────────
# Namespace
# ─────────────────────────────────────────────
resource "kubernetes_namespace" "team" {
  metadata {
    name = var.namespace

    labels = {
      "team"                                          = var.team_name
      "environment"                                   = var.environment
      "cost-center"                                   = var.cost_center
      "managed-by"                                    = "terraform"
      # Enforce restricted Pod Security Standard
      "pod-security.kubernetes.io/enforce"            = "restricted"
      "pod-security.kubernetes.io/enforce-version"    = "latest"
      "pod-security.kubernetes.io/audit"              = "restricted"
      "pod-security.kubernetes.io/audit-version"      = "latest"
      "pod-security.kubernetes.io/warn"               = "restricted"
      "pod-security.kubernetes.io/warn-version"       = "latest"
    }

    annotations = {
      "description" = "Namespace for team ${var.team_name}"
    }
  }
}

# ─────────────────────────────────────────────
# Resource Quota
# ─────────────────────────────────────────────
resource "kubernetes_resource_quota" "team" {
  metadata {
    name      = "${var.team_name}-quota"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.cpu"      = var.quota.limits_cpu
      "limits.memory"   = var.quota.limits_memory
      "count/pods"      = var.quota.max_pods
      "count/services"  = var.quota.max_services
      "count/secrets"   = var.quota.max_secrets
      "count/configmaps" = var.quota.max_configmaps
      "persistentvolumeclaims" = var.quota.max_pvcs
      "requests.storage"       = var.quota.max_storage
    }
  }
}

# ─────────────────────────────────────────────
# Limit Range (default requests/limits)
# ─────────────────────────────────────────────
resource "kubernetes_limit_range" "team" {
  metadata {
    name      = "${var.team_name}-limits"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
      max = {
        cpu    = "4"
        memory = "8Gi"
      }
      min = {
        cpu    = "10m"
        memory = "32Mi"
      }
    }

    limit {
      type = "Pod"
      max = {
        cpu    = "8"
        memory = "16Gi"
      }
    }

    limit {
      type = "PersistentVolumeClaim"
      max = {
        storage = "100Gi"
      }
    }
  }
}

# ─────────────────────────────────────────────
# Network Policies
# ─────────────────────────────────────────────

# Default deny all ingress and egress
resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# Allow intra-namespace traffic
resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    pod_selector {}

    ingress {
      from {
        pod_selector {}
      }
    }

    egress {
      to {
        pod_selector {}
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}

# Allow DNS egress (required for all pods)
resource "kubernetes_network_policy" "allow_dns" {
  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    pod_selector {}

    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }

    policy_types = ["Egress"]
  }
}

# Allow ingress from ingress controller
resource "kubernetes_network_policy" "allow_ingress_controller" {
  metadata {
    name      = "allow-ingress-controller"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    pod_selector {}

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
      }
    }

    policy_types = ["Ingress"]
  }
}

# Allow monitoring scraping
resource "kubernetes_network_policy" "allow_monitoring" {
  metadata {
    name      = "allow-monitoring"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  spec {
    pod_selector {}

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "monitoring"
          }
        }
      }
      ports {
        port     = "9090"
        protocol = "TCP"
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    policy_types = ["Ingress"]
  }
}

# ─────────────────────────────────────────────
# RBAC
# ─────────────────────────────────────────────

# Namespace Admin role (team leads)
resource "kubernetes_role" "namespace_admin" {
  metadata {
    name      = "namespace-admin"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

# Developer role (read + exec)
resource "kubernetes_role" "developer" {
  metadata {
    name      = "developer"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  rule {
    api_groups = ["", "apps", "batch", "extensions", "networking.k8s.io"]
    resources  = ["pods", "pods/log", "pods/exec", "deployments", "replicasets", "services", "ingresses", "jobs", "cronjobs", "configmaps", "events"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec", "pods/portforward"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }
}

# Viewer role (read-only)
resource "kubernetes_role" "viewer" {
  metadata {
    name      = "viewer"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

# Bind admin group
resource "kubernetes_role_binding" "namespace_admins" {
  metadata {
    name      = "namespace-admins"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.namespace_admin.metadata[0].name
  }

  dynamic "subject" {
    for_each = var.admin_groups
    content {
      kind      = "Group"
      name      = subject.value
      api_group = "rbac.authorization.k8s.io"
    }
  }
}

# Bind developer group
resource "kubernetes_role_binding" "developers" {
  metadata {
    name      = "developers"
    namespace = kubernetes_namespace.team.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.developer.metadata[0].name
  }

  dynamic "subject" {
    for_each = var.developer_groups
    content {
      kind      = "Group"
      name      = subject.value
      api_group = "rbac.authorization.k8s.io"
    }
  }
}

# ─────────────────────────────────────────────
# Workload Identity - GCP Service Account
# ─────────────────────────────────────────────
resource "google_service_account" "team_gsa" {
  project      = var.project_id
  account_id   = "${var.team_name}-gsa"
  display_name = "GCP Service Account for team ${var.team_name}"
}

# Kubernetes Service Account
resource "kubernetes_service_account" "team_ksa" {
  metadata {
    name      = "${var.team_name}-ksa"
    namespace = kubernetes_namespace.team.metadata[0].name

    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.team_gsa.email
    }
  }
}

# Bind GSA → KSA (Workload Identity)
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.team_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${kubernetes_service_account.team_ksa.metadata[0].name}]"
}

# Bind team GSA to required GCP roles
resource "google_project_iam_member" "team_gsa_roles" {
  for_each = toset(var.gcp_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.team_gsa.email}"
}
