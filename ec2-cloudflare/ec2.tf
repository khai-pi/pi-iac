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
      # Copy files to the instance
      write_files : [
        {
          path : "/etc/nginx/sites-available/tunnel-proxy"
          content : templatefile("${path.module}/nginx-config.tpl", {
            domain = var.cloudflare_zone_domain
          })
          permissions : "0644"
        },
        {
          path : "/tmp/setup-script.sh"
          content : templatefile("${path.module}/setup-script.sh", {
            tunnel_id       = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.id
            credentials_json = jsonencode({
              AccountTag   = var.cloudflare_account_id
              TunnelSecret = random_id.tunnel_secret.b64_std
              TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.auto_tunnel.id
            })
            domain = var.cloudflare_zone_domain
          })
          permissions : "0755"
        }
      ]
      runcmd : [
        "/tmp/setup-script.sh"
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