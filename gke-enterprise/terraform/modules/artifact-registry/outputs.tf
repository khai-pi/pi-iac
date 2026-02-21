output "container_registry_url" {
  description = "Docker-format URL for the container registry"
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}"
}

output "helm_registry_url" {
  description = "URL for the Helm chart registry"
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.helm.repository_id}"
}

output "container_repository_id" {
  value = google_artifact_registry_repository.containers.repository_id
}

output "helm_repository_id" {
  value = google_artifact_registry_repository.helm.repository_id
}
