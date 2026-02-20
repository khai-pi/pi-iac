variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "location" {
  description = "Artifact Registry location (region or multi-region)"
  type        = string
  default     = "europe-west1"
}

variable "reader_service_accounts" {
  description = "List of service account emails with read access (GKE nodes)"
  type        = list(string)
  default     = []
}

variable "writer_service_accounts" {
  description = "List of service account emails with write access (CI/CD)"
  type        = list(string)
  default     = []
}
