output "network_id" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_ids" {
  description = "Map of subnet names to their self-links"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.id }
}

output "subnet_names" {
  description = "Map of subnet names to their names"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.name }
}

output "pods_range_names" {
  description = "Map of subnet names to their pod secondary range names"
  value       = { for k, v in google_compute_subnetwork.subnets : k => "${k}-pods" }
}

output "services_range_names" {
  description = "Map of subnet names to their services secondary range names"
  value       = { for k, v in google_compute_subnetwork.subnets : k => "${k}-services" }
}
