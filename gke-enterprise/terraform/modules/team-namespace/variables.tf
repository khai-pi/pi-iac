variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace name"
  type        = string
}

variable "team_name" {
  description = "Short team identifier (used in resource names)"
  type        = string
}

variable "environment" {
  description = "Environment label (dev/staging/prod)"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing attribution"
  type        = string
}

variable "quota" {
  description = "Resource quota configuration for the namespace"
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    max_pods        = string
    max_services    = string
    max_secrets     = string
    max_configmaps  = string
    max_pvcs        = string
    max_storage     = string
  })
  default = {
    requests_cpu    = "10"
    requests_memory = "20Gi"
    limits_cpu      = "20"
    limits_memory   = "40Gi"
    max_pods        = "50"
    max_services    = "20"
    max_secrets     = "50"
    max_configmaps  = "50"
    max_pvcs        = "10"
    max_storage     = "500Gi"
  }
}

variable "admin_groups" {
  description = "List of Google Groups (email) to grant namespace-admin role"
  type        = list(string)
  default     = []
}

variable "developer_groups" {
  description = "List of Google Groups (email) to grant developer role"
  type        = list(string)
  default     = []
}

variable "gcp_roles" {
  description = "List of GCP IAM roles to grant the team's service account"
  type        = list(string)
  default     = []
}
