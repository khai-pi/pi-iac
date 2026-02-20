variable "org_name" {
  description = "Short organization name used in resource naming (e.g. 'myorg')"
  type        = string
}

variable "org_id" {
  description = "GCP Organization ID (numeric)"
  type        = string
  default     = ""
}

variable "host_project_id" {
  description = "GCP project ID for the Shared VPC host"
  type        = string
}

variable "cluster_project_id" {
  description = "GCP project ID where GKE clusters are deployed"
  type        = string
}

variable "shared_services_project_id" {
  description = "GCP project ID for shared services (Artifact Registry, KMS)"
  type        = string
}

variable "primary_region" {
  description = "Primary GCP region"
  type        = string
  default     = "europe-west1"
}

variable "dr_region" {
  description = "Disaster Recovery GCP region"
  type        = string
  default     = "us-central1"
}

variable "primary_master_cidr" {
  description = "CIDR for the primary cluster's control plane (/28)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "dr_master_cidr" {
  description = "CIDR for the DR cluster's control plane (/28)"
  type        = string
  default     = "172.16.0.16/28"
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the Kubernetes API server"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed through the Cloud Armor WAF"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "internal_domain" {
  description = "Internal DNS domain"
  type        = string
  default     = "internal.example.com"
}

variable "cicd_service_account_email" {
  description = "Email of the CI/CD service account (Cloud Build / GitHub Actions)"
  type        = string
}

variable "argocd_admin_password" {
  description = "ArgoCD admin password (bcrypt hashed)"
  type        = string
  sensitive   = true
}
