output "primary_cluster_name" {
  description = "Name of the primary GKE cluster"
  value       = module.gke_primary.cluster_name
}

output "dr_cluster_name" {
  description = "Name of the DR GKE cluster"
  value       = module.gke_dr.cluster_name
}

output "container_registry_url" {
  description = "Artifact Registry URL for container images"
  value       = module.artifact_registry.container_registry_url
}

output "helm_registry_url" {
  description = "Artifact Registry URL for Helm charts"
  value       = module.artifact_registry.helm_registry_url
}

output "waf_policy_name" {
  description = "Cloud Armor WAF policy name"
  value       = module.security.waf_policy_name
}

output "team_namespaces" {
  description = "Map of team namespaces and their Workload Identity GSAs"
  value = {
    payments = {
      namespace = module.team_payments.namespace
      gsa_email = module.team_payments.gsa_email
    }
    identity = {
      namespace = module.team_identity.namespace
      gsa_email = module.team_identity.gsa_email
    }
    data = {
      namespace = module.team_data.namespace
      gsa_email = module.team_data.gsa_email
    }
  }
}

output "get_credentials_primary" {
  description = "gcloud command to get credentials for the primary cluster"
  value       = "gcloud container clusters get-credentials ${module.gke_primary.cluster_name} --region=${var.primary_region} --project=${var.cluster_project_id}"
}

output "get_credentials_dr" {
  description = "gcloud command to get credentials for the DR cluster"
  value       = "gcloud container clusters get-credentials ${module.gke_dr.cluster_name} --region=${var.dr_region} --project=${var.cluster_project_id}"
}
