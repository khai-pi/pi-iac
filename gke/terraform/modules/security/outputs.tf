output "waf_policy_id" {
  description = "Cloud Armor security policy ID"
  value       = google_compute_security_policy.waf.id
}

output "waf_policy_name" {
  description = "Cloud Armor security policy name"
  value       = google_compute_security_policy.waf.name
}

output "secret_ids" {
  description = "Map of created Secret Manager secret IDs"
  value       = { for k, v in google_secret_manager_secret.platform_secrets : k => v.secret_id }
}
