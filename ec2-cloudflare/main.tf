provider "aws" {
  region = "us-east-1"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "random" {}

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
  name       = "aws-tunnel-${var.instance_name}"
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
      hostname = var.tunnel_hostname
      service  = "http://localhost:80"
    }

    # Catch-all rule (required)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# User data script to install and configure cloudflared
data "cloudinit_config" "tunnel_config" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = jsonencode({
      package_update : true
      package_upgrade : true
      packages : [
        "curl",
        "nginx"
      ]
      runcmd : [
        # Create cloudflared directory FIRST
        "mkdir -p /etc/cloudflared",
        
        # Write config files
        "cat > /etc/cloudflared/config.yml <<'EOT'\ntunnel: ${cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.id}\ncredentials-file: /etc/cloudflared/credentials.json\nEOT",
        
        "cat > /etc/cloudflared/credentials.json <<'EOT'\n${jsonencode({
          AccountTag   = var.cloudflare_account_id
          TunnelSecret = random_id.tunnel_secret.b64_std
          TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.id
        })}\nEOT",
        
        # Set permissions
        "chmod 600 /etc/cloudflared/config.yml",
        "chmod 600 /etc/cloudflared/credentials.json",
        
        # Install cloudflared
        "curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb",
        "dpkg -i /tmp/cloudflared.deb",
        
        # Setup cloudflared as a service
        "cloudflared --config /etc/cloudflared/config.yml service install",
        "systemctl start cloudflared",
        "systemctl enable cloudflared",
        
        # Setup nginx
        "echo '<h1>Hello from Cloudflare Tunnel on AWS!</h1>' > /var/www/html/index.html",
        "systemctl start nginx",
        "systemctl enable nginx"
      ]
    })
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "pi-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24"]

  enable_dns_hostnames = true
}

resource "aws_security_group" "security_group" {
  name        = "cloudflare-tunnel-security-group"
  description = "Allow SSH inbound traffic"
  vpc_id      = module.vpc.vpc_id

  # Inbound: Only SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP for security
  }

  # Outbound: Allow all (Cloudflare Tunnel needs HTTPS outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids      = [aws_security_group.security_group.id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  user_data = data.cloudinit_config.tunnel_config.rendered

  tags = {
    Name = var.instance_name
  }
}
