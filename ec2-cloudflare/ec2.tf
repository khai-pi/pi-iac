data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
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
