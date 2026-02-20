variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cluster_id" {
  description = "GKE cluster ID (self-link)"
  type        = string
}

variable "pool_name" {
  description = "Name of the node pool"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment label (dev/staging/prod)"
  type        = string
}

variable "cost_center" {
  description = "Cost center tag for billing attribution"
  type        = string
  default     = "platform"
}

variable "machine_type" {
  description = "GCE machine type for nodes"
  type        = string
  default     = "n2-standard-4"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "Boot disk type: pd-standard, pd-ssd, pd-balanced"
  type        = string
  default     = "pd-balanced"
}

variable "min_node_count" {
  description = "Minimum number of nodes per zone"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes per zone"
  type        = number
  default     = 10
}

variable "use_spot_instances" {
  description = "Use Spot (preemptible) instances for this node pool"
  type        = bool
  default     = false
}

variable "node_service_account_email" {
  description = "Email of the service account to assign to nodes"
  type        = string
}

variable "taints" {
  description = "List of taints to apply to nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "extra_labels" {
  description = "Additional labels to apply to nodes"
  type        = map(string)
  default     = {}
}

variable "extra_tags" {
  description = "Additional network tags for firewall rules"
  type        = list(string)
  default     = []
}

variable "local_ssd_count" {
  description = "Number of local SSDs to attach (0 to disable)"
  type        = number
  default     = 0
}
