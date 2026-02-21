output "namespace" {
  description = "Kubernetes namespace name"
  value       = kubernetes_namespace.team.metadata[0].name
}

output "ksa_name" {
  description = "Kubernetes Service Account name"
  value       = kubernetes_service_account.team_ksa.metadata[0].name
}

output "gsa_email" {
  description = "GCP Service Account email for Workload Identity"
  value       = google_service_account.team_gsa.email
}
