variable "org_name" {
  type = string
}

variable "host_project_id" {
  type = string
}

variable "cluster_project_id" {
  type = string
}

variable "primary_region" {
  type    = string
  default = "europe-west1"
}

variable "primary_master_cidr" {
  type    = string
  default = "172.16.1.0/28"
}

variable "master_authorized_networks" {
  type    = list(string)
  default = ["10.0.0.0/8"]
}

variable "internal_domain" {
  type    = string
  default = "internal.example.com"
}
