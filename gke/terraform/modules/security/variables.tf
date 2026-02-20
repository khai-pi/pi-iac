variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
}

variable "primary_region" {
  description = "Primary GCP region"
  type        = string
}

variable "dr_region" {
  description = "DR GCP region (empty string to disable)"
  type        = string
  default     = ""
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed through Cloud Armor WAF"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "secret_ids" {
  description = "Set of Secret Manager secret IDs to create"
  type        = set(string)
  default     = []
}

variable "org_id" {
  description = "GCP Organization ID (leave empty to skip org policies)"
  type        = string
  default     = ""
}
