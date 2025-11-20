# Generate random tunnel secret
resource "random_id" "tunnel_secret" {
  byte_length = 35
}

# Get the zone ID for domain
data "cloudflare_zone" "domain" {
  name = var.cloudflare_zone_domain
}

# Create Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "auto_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "tunnel-${var.instance_name}"
  secret     = random_id.tunnel_secret.b64_std
}

# Create DNS record pointing to the tunnel
resource "cloudflare_record" "tunnel_dns" {
  zone_id = data.cloudflare_zone.domain.id
  name    = var.cloudflare_subdomain
  content = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.cname
  type    = "CNAME"
  proxied = true
}

# Configure Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "auto_tunnel" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.id

  config {
    warp_routing {
      enabled = true
    }

    ingress_rule {
      hostname = "${var.cloudflare_subdomain}.${var.cloudflare_zone_domain}"
      service  = "http://localhost:80"
    }

    # Catch-all rule (required)
    ingress_rule {
      service = "http_status:404"
    }
  }
}


