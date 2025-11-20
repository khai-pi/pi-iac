output "instance_hostname" {
  description = "Private DNS name of the EC2 instance."
  value       = aws_instance.app_server.private_dns
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.id
}

output "tunnel_cname" {
  description = "Cloudflare Tunnel CNAME"
  value       = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.cname
}

output "tunnel_url" {
  description = "Public URL for accessing application"
  value       = "https://${var.tunnel_hostname}"
}