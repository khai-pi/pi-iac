#!/bin/bash
set -e

# Create cloudflared directory
mkdir -p /etc/cloudflared

# Write cloudflared config
cat > /etc/cloudflared/config.yml <<'EOT'
tunnel: ${tunnel_id}
credentials-file: /etc/cloudflared/credentials.json
EOT

# Write cloudflared credentials
cat > /etc/cloudflared/credentials.json <<'EOT'
${credentials_json}
EOT

# Set permissions
chmod 600 /etc/cloudflared/config.yml
chmod 600 /etc/cloudflared/credentials.json

# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb

# Setup cloudflared as a service
cloudflared --config /etc/cloudflared/config.yml service install
systemctl start cloudflared
systemctl enable cloudflared

# Setup nginx
echo '<h1>Hello from Cloudflare Tunnel on AWS!</h1><p>Main domain: ${domain}</p>' > /var/www/html/index.html

# Remove default nginx config and enable our config
rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/tunnel-proxy /etc/nginx/sites-enabled/

# Test and restart nginx
nginx -t
systemctl restart nginx
systemctl enable nginx