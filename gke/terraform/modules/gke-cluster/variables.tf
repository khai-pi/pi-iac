variable "project_id" {
  description = "GCP project ID where the cluster will be created"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster"
  type        = string
}

variable "network_id" {
  description = "VPC network self-link"
  type        = string
}

variable "subnetwork_id" {
  description = "Subnet self-link for the cluster nodes"
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary IP range for pods"
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary IP range for services"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the GKE control plane (must be /28)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks allowed to access the Kubernetes API server"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of: RAPID, REGULAR, STABLE"
  }
}

variable "binary_auth_enforcement_mode" {
  description = "Binary Authorization enforcement mode"
  type        = string
  default     = "ENFORCED_BLOCK_AND_AUDIT_LOG"

  validation {
    condition     = contains(["ENFORCED_BLOCK_AND_AUDIT_LOG", "DRYRUN_AUDIT_LOG_ONLY"], var.binary_auth_enforcement_mode)
    error_message = "Must be ENFORCED_BLOCK_AND_AUDIT_LOG or DRYRUN_AUDIT_LOG_ONLY"
  }
}

variable "enable_node_auto_provisioning" {
  description = "Enable Node Auto-Provisioning (creates node pools automatically)"
  type        = bool
  default     = false
}
