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
      write_files : [
        {
          path : "/etc/nginx/sites-available/tunnel-proxy"
          content : <<-EOT
            # Main domain
            server {
                listen 80;
                server_name ${var.cloudflare_subdomain}.${var.cloudflare_zone_domain};
                
                location / {
                    root /var/www/html;
                    index index.html;
                }
            }

            # Example app subdomain
            server {
                listen 80;
                server_name app.${var.cloudflare_subdomain}.${var.cloudflare_zone_domain};
                
                location / {
                    proxy_pass http://localhost:3000;
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection 'upgrade';
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_cache_bypass $http_upgrade;
                }
            }

            # Example API subdomain
            server {
                listen 80;
                server_name api.${var.cloudflare_subdomain}.${var.cloudflare_zone_domain};
                
                location / {
                    proxy_pass http://localhost:4000;
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection 'upgrade';
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_cache_bypass $http_upgrade;
                }
            }

            # Default catch-all for undefined subdomains
            server {
                listen 80 default_server;
                server_name _;
                
                location / {
                    return 200 '<h1>Subdomain not configured</h1><p>Please configure this subdomain in nginx</p>';
                    add_header Content-Type text/html;
                }
            }
          EOT
          permissions : "0644"
        }
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
        "echo '<h1>Hello from Cloudflare Tunnel on AWS!</h1><p>Main domain: ${var.cloudflare_subdomain}.${var.cloudflare_zone_domain}</p>' > /var/www/html/index.html",
        
        # Remove default nginx config and enable our config
        "rm -f /etc/nginx/sites-enabled/default",
        "ln -s /etc/nginx/sites-available/tunnel-proxy /etc/nginx/sites-enabled/",
        
        # Test and restart nginx
        "nginx -t",
        "systemctl restart nginx",
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