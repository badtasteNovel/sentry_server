#!/usr/bin/env bash
# Sentry self-hosted bootstrap — runs once on EC2 first boot via cloud-init
set -euo pipefail
exec > >(tee /var/log/sentry-bootstrap.log | logger -t sentry-bootstrap) 2>&1

SENTRY_VERSION="${sentry_version}"
COMPOSE_PROFILE="${compose_profile}"
DOMAIN="${domain_name}"
ADMIN_EMAIL="${sentry_admin_email}"
ADMIN_PASSWORD="${sentry_admin_password}"
SMTP_HOST="${smtp_host}"
SMTP_PORT="${smtp_port}"
SMTP_USER="${smtp_user}"
SMTP_PASSWORD="${smtp_password}"
SMTP_USE_TLS="${smtp_use_tls}"

DATA_DEVICE="/dev/xvdf"
DATA_MOUNT="/data"
SENTRY_DIR="/opt/sentry"

# ─── 1. System packages ───────────────────────────────────────────────────────

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  jq \
  certbot \
  python3-certbot-nginx \
  nginx \
  awscli \
  unzip \
  git

# ─── 2. Docker (official repo) ────────────────────────────────────────────────

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
usermod -aG docker ubuntu

# ─── 3. Format + mount data volume ────────────────────────────────────────────

# Wait for the EBS volume to appear (can take a few seconds after attach)
for i in $(seq 1 30); do
  test -b "$DATA_DEVICE" && break
  echo "Waiting for $DATA_DEVICE... ($i/30)"
  sleep 2
done

if ! blkid "$DATA_DEVICE" | grep -q ext4; then
  mkfs.ext4 -L sentry-data "$DATA_DEVICE"
fi

mkdir -p "$DATA_MOUNT"
echo "LABEL=sentry-data  $DATA_MOUNT  ext4  defaults,nofail  0  2" >> /etc/fstab
mount -a

# Sentry docker volumes will live here so they survive instance replacement
mkdir -p \
  "$DATA_MOUNT/sentry-postgres" \
  "$DATA_MOUNT/sentry-redis" \
  "$DATA_MOUNT/sentry-zookeeper" \
  "$DATA_MOUNT/sentry-kafka" \
  "$DATA_MOUNT/sentry-clickhouse" \
  "$DATA_MOUNT/sentry-symbolicator" \
  "$DATA_MOUNT/sentry-uploads"

chown -R 999:999 "$DATA_MOUNT" 2>/dev/null || true

# ─── 4. Clone sentry self-hosted ──────────────────────────────────────────────

git clone \
  --depth 1 \
  --branch "$SENTRY_VERSION" \
  https://github.com/getsentry/self-hosted.git \
  "$SENTRY_DIR"

cd "$SENTRY_DIR"

# ─── 5. Override docker volume paths to data volume ───────────────────────────

cat > "$SENTRY_DIR/docker-compose.override.yml" <<OVERRIDE
version: "3.9"
volumes:
  sentry-postgres:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-postgres
  sentry-redis:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-redis
  sentry-zookeeper:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-zookeeper
  sentry-kafka:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-kafka
  sentry-clickhouse:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-clickhouse
  sentry-symbolicator:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-symbolicator
  sentry-uploads:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DATA_MOUNT/sentry-uploads
OVERRIDE

# ─── 6. sentry/config.yml — mail + URL ────────────────────────────────────────

# install.sh copies .example files on first run, but we pre-seed them
cp sentry/config.example.yml sentry/config.yml
cp sentry/sentry.conf.example.py sentry/sentry.conf.py

# Set the base URL Sentry generates links from
sed -i "s|system.url-prefix:.*|system.url-prefix: 'https://$DOMAIN'|" sentry/config.yml

# Mail config
if [[ -n "$SMTP_HOST" ]]; then
cat >> sentry/config.yml <<MAIL

mail.backend: 'smtp'
mail.host: '$SMTP_HOST'
mail.port: $SMTP_PORT
mail.username: '$SMTP_USER'
mail.password: '$SMTP_PASSWORD'
mail.use-tls: $SMTP_USE_TLS
mail.from: 'sentry@$DOMAIN'
MAIL
fi

# ─── 7. Run official installer (non-interactive) ───────────────────────────────

export COMPOSE_PROFILES="$COMPOSE_PROFILE"
export SENTRY_ADMIN_USERNAME="$ADMIN_EMAIL"
export SENTRY_ADMIN_PASSWORD="$ADMIN_PASSWORD"
export SKIP_USER_CREATION=0

TERM=dumb NO_COLOR=1 bash install.sh --no-user-prompt

# ─── 8. Create systemd service ────────────────────────────────────────────────

cat > /etc/systemd/system/sentry.service <<SERVICE
[Unit]
Description=Sentry self-hosted
Requires=docker.service
After=docker.service network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$SENTRY_DIR
Environment=COMPOSE_PROFILES=$COMPOSE_PROFILE
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300
TimeoutStopSec=120
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable sentry

# ─── 9. Nginx reverse proxy + Let's Encrypt ───────────────────────────────────

# Temporary HTTP-only config so certbot can perform ACME challenge
cat > /etc/nginx/sites-available/sentry <<NGINX_HTTP
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
NGINX_HTTP

mkdir -p /var/www/certbot
ln -sf /etc/nginx/sites-available/sentry /etc/nginx/sites-enabled/sentry
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Issue TLS certificate
certbot certonly \
  --webroot \
  -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$ADMIN_EMAIL" \
  --agree-tos \
  --non-interactive \
  --keep-until-expiring

# Full HTTPS config with proxy_pass to Sentry (port 9000 = web service)
cat > /etc/nginx/sites-available/sentry <<NGINX_HTTPS
upstream sentry_web {
    server 127.0.0.1:9000;
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;

    client_max_body_size 20m;

    location / {
        proxy_pass         http://sentry_web;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        proxy_redirect     off;
    }
}
NGINX_HTTPS

nginx -t && systemctl reload nginx

# Certbot auto-renew
systemctl enable --now certbot.timer

# ─── 10. Start Sentry ─────────────────────────────────────────────────────────

systemctl start sentry

echo "Bootstrap complete. Sentry $SENTRY_VERSION is starting at https://$DOMAIN"
echo "Monitor progress: journalctl -u sentry -f"
