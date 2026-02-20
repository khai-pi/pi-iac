variable "prefix" {
  description = "Resource name prefix (e.g. 'myorg-prod')"
  type        = string
}

variable "host_project_id" {
  description = "GCP project ID for the Shared VPC host project"
  type        = string
}

variable "service_project_ids" {
  description = "List of service project IDs to attach to the Shared VPC"
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = "Map of subnet configurations keyed by subnet name"
  type = map(object({
    region        = string
    ip_cidr_range = string
    pods_cidr     = string
    services_cidr = string
  }))
}

variable "regions" {
  description = "Map of region identifiers to region names (for routers/NAT)"
  type        = map(string)
  # e.g. { primary = "europe-west1", dr = "us-central1" }
}

variable "master_ipv4_cidrs" {
  description = "CIDR ranges of GKE control plane (for firewall rules)"
  type        = list(string)
  default     = ["172.16.0.0/28", "172.16.0.16/28"]
}

variable "internal_domain" {
  description = "Internal DNS domain (e.g. 'internal.example.com')"
  type        = string
  default     = "internal.example.com"
}
