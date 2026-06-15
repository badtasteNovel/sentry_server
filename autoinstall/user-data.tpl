#cloud-config
autoinstall:
  version: 1

  locale: en_US.UTF-8
  keyboard:
    layout: us
    variant: ''

  network:
    version: 2
    ethernets:
      any-nic:
        match:
          name: "e*"
        dhcp4: false
        addresses: [__STATIC_IP__]
        routes:
          - to: default
            via: __GATEWAY__
        nameservers:
          addresses: [__DNS__]

  # 系統裝在第一顆磁碟 (sda)，第二顆 (sdb) 由 bootstrap 格式化掛載成 /data
  storage:
    layout:
      name: direct

  identity:
    hostname: sentry
    username: ubuntu
    password: '__UBUNTU_PASSWORD_HASH__'

  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - '__SSH_PUBLIC_KEY__'

  packages:
    - curl
    - git
    - ca-certificates
    - gnupg
    - lsb-release
    - jq

  late-commands:

    # ── 1. 寫入 Sentry 設定檔 ─────────────────────────────────────────────
    - |
      cat > /target/etc/sentry-install.conf << 'CONF'
      SENTRY_VERSION="__SENTRY_VERSION__"
      COMPOSE_PROFILE="__COMPOSE_PROFILE__"
      DOMAIN="__SENTRY_DOMAIN__"
      ADMIN_EMAIL="__ADMIN_EMAIL__"
      ADMIN_PASSWORD="__ADMIN_PASSWORD__"
      SMTP_HOST="__SMTP_HOST__"
      SMTP_PORT="__SMTP_PORT__"
      SMTP_USER="__SMTP_USER__"
      SMTP_PASSWORD="__SMTP_PASSWORD__"
      SMTP_USE_TLS="__SMTP_USE_TLS__"
      SSH_PORT="__SSH_PORT__"
      DATA_DEVICE="/dev/sda"
      DATA_MOUNT="/data"
      SENTRY_DIR="/opt/sentry"
      CONF

    # ── 2. 寫入 bootstrap script ──────────────────────────────────────────
    - |
      python3 << 'PYEOF'
      script = r'''#!/usr/bin/env bash
      # Sentry first-boot installer — reads config from /etc/sentry-install.conf
      set -euo pipefail
      exec > >(tee /var/log/sentry-bootstrap.log | logger -t sentry-bootstrap) 2>&1

      source /etc/sentry-install.conf

      # ── Docker ────────────────────────────────────────────────────────────
      export DEBIAN_FRONTEND=noninteractive
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update -y
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      systemctl enable --now docker
      usermod -aG docker ubuntu

      # ── Format + mount /dev/sda as /data ──────────────────────────────────
      for i in $(seq 1 30); do
        test -b "$DATA_DEVICE" && break
        echo "Waiting for $DATA_DEVICE... ($i/30)"
        sleep 2
      done
      if ! blkid "$DATA_DEVICE" 2>/dev/null | grep -q ext4; then
        mkfs.ext4 -L sentry-data "$DATA_DEVICE"
      fi
      mkdir -p "$DATA_MOUNT"
      echo "LABEL=sentry-data  $DATA_MOUNT  ext4  defaults,nofail  0  2" >> /etc/fstab
      mount -a
      mkdir -p \
        "$DATA_MOUNT/sentry-postgres" \
        "$DATA_MOUNT/sentry-redis" \
        "$DATA_MOUNT/sentry-zookeeper" \
        "$DATA_MOUNT/sentry-kafka" \
        "$DATA_MOUNT/sentry-clickhouse" \
        "$DATA_MOUNT/sentry-symbolicator" \
        "$DATA_MOUNT/sentry-uploads"
      chown -R 999:999 "$DATA_MOUNT" 2>/dev/null || true

      # ── Clone sentry self-hosted ──────────────────────────────────────────
      git clone --depth 1 --branch "$SENTRY_VERSION" \
        https://github.com/getsentry/self-hosted.git "$SENTRY_DIR"
      cd "$SENTRY_DIR"

      # ── Sentry config ─────────────────────────────────────────────────────
      cp sentry/config.example.yml sentry/config.yml
      cp sentry/sentry.conf.example.py sentry/sentry.conf.py
      sed -i "s|system.url-prefix:.*|system.url-prefix: 'https://$DOMAIN'|" sentry/config.yml
      echo "CSRF_TRUSTED_ORIGINS = ['https://$DOMAIN']" >> sentry/sentry.conf.py
      if [[ -n "$SMTP_HOST" ]]; then
        cat >> sentry/config.yml << MAIL

      mail.backend: 'smtp'
      mail.host: '$SMTP_HOST'
      mail.port: $SMTP_PORT
      mail.username: '$SMTP_USER'
      mail.password: '$SMTP_PASSWORD'
      mail.use-tls: $SMTP_USE_TLS
      mail.from: 'sentry@$DOMAIN'
      MAIL
      fi

      # ── Run official installer ────────────────────────────────────────────
      export COMPOSE_PROFILES="$COMPOSE_PROFILE"
      export SENTRY_ADMIN_EMAIL="$ADMIN_EMAIL"
      export SENTRY_ADMIN_PASSWORD="$ADMIN_PASSWORD"
      export SKIP_USER_CREATION=0
      export REPORT_SELF_HOSTED_ISSUES=0
      TERM=dumb NO_COLOR=1 bash install.sh --no-user-prompt

      # ── Sentry systemd service ────────────────────────────────────────────
      cat > /etc/systemd/system/sentry.service << SERVICE
      [Unit]
      Description=Sentry self-hosted
      Requires=docker.service
      After=docker.service network-online.target

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      WorkingDirectory=$SENTRY_DIR
      Environment=COMPOSE_PROFILES=$COMPOSE_PROFILE
      ExecStart=/usr/bin/docker compose up -d --remove-orphans
      ExecStop=/usr/bin/docker compose down
      TimeoutStartSec=300
      TimeoutStopSec=120

      [Install]
      WantedBy=multi-user.target
      SERVICE
      systemctl daemon-reload
      systemctl enable sentry

      # ── Nginx + self-signed TLS ───────────────────────────────────────────
      apt-get install -y nginx
      openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/ssl/private/sentry.key \
        -out /etc/ssl/certs/sentry.crt \
        -subj "/CN=$DOMAIN"
      cat > /etc/nginx/sites-available/sentry << NGINX_CONF
      upstream sentry_web { server 127.0.0.1:9000; }
      server {
          listen 80;
          server_name _;
          return 301 https://\$host\$request_uri;
      }
      server {
          listen 443 ssl http2;
          server_name _;
          ssl_certificate     /etc/ssl/certs/sentry.crt;
          ssl_certificate_key /etc/ssl/private/sentry.key;
          ssl_protocols TLSv1.2 TLSv1.3;
          client_max_body_size 20m;
          location / {
              proxy_pass http://sentry_web;
              proxy_set_header Host \$host;
              proxy_set_header X-Real-IP \$remote_addr;
              proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto \$scheme;
              proxy_read_timeout 120s;
          }
      }
      NGINX_CONF
      ln -sf /etc/nginx/sites-available/sentry /etc/nginx/sites-enabled/sentry
      rm -f /etc/nginx/sites-enabled/default
      nginx -t && systemctl enable --now nginx

      # ── UFW ──────────────────────────────────────────────────────────────────
      apt-get install -y ufw
      sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
      ufw default deny incoming
      ufw default allow outgoing
      ufw allow from 192.168.0.0/24 to any port "$SSH_PORT"
      ufw allow from 192.168.0.0/24 to any port 443
      ufw --force enable

      # ── Start Sentry ──────────────────────────────────────────────────────
      systemctl start sentry
      echo "=== Bootstrap complete. Sentry $SENTRY_VERSION running at https://$DOMAIN ==="
      '''
      with open('/target/opt/sentry-bootstrap.sh', 'w') as f:
          f.write(script)
      import os
      os.chmod('/target/opt/sentry-bootstrap.sh', 0o755)
      PYEOF

    # ── 3. Custom SSH port ────────────────────────────────────────────────
    - echo 'Port __SSH_PORT__' > /target/etc/ssh/sshd_config.d/99-custom.conf

    # ── 4. Systemd first-boot service ─────────────────────────────────────
    - |
      cat > /target/etc/systemd/system/sentry-bootstrap.service << 'SVC'
      [Unit]
      Description=Sentry first-boot installation
      After=network-online.target
      Wants=network-online.target
      ConditionPathExists=!/var/log/sentry-bootstrap.log

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/opt/sentry-bootstrap.sh
      StandardOutput=journal+console
      TimeoutStartSec=1800

      [Install]
      WantedBy=multi-user.target
      SVC

    # ── 5. Enable first-boot service ───────────────────────────────────────
    - curtin in-target -- systemctl enable sentry-bootstrap.service

    # ── 6. TTY autologin on console (ESXi VM console = admin-only access) ─
    - mkdir -p /target/etc/systemd/system/getty@tty1.service.d
    - printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin ubuntu --noclear %%I linux\n' > /target/etc/systemd/system/getty@tty1.service.d/autologin.conf

    # ── 7. ubuntu passwordless sudo ──────────────────────────────────────────
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/99-ubuntu-nopasswd
    - chmod 440 /target/etc/sudoers.d/99-ubuntu-nopasswd
