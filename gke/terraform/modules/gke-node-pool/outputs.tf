output "node_pool_name" {
  description = "Name of the node pool"
  value       = google_container_node_pool.pool.name
}

output "node_pool_id" {
  description = "ID of the node pool"
  value       = google_container_node_pool.pool.id
}

output "instance_group_urls" {
  description = "List of managed instance groups in this node pool"
  value       = google_container_node_pool.pool.managed_instance_group_urls
}
