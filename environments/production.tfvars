# ─── production.tfvars ───────────────────────────────────────────────────────
# Copy this file and fill in real values.
# NEVER commit passwords/secrets — use a secrets manager or CI/CD env vars.
# Usage: tofu apply -var-file=environments/production.tfvars

aws_region  = "ap-southeast-1"
environment = "production"

# Networking — leave empty to use the default VPC + first public subnet,
# or set explicit IDs from your existing VPC.
vpc_id    = ""
subnet_id = ""

# EC2 — t3.xlarge = 4 vCPU, 16 GB RAM (required for errors-only profile)
instance_type       = "t3.xlarge"
compose_profile     = "errors-only"
root_volume_size_gb = 100
data_volume_size_gb = 200

# Leave empty to auto-generate a key pair (private key saved to ./keys/)
key_pair_name = ""

# DNS — set your domain and Route53 zone ID
domain_name     = "sentry.yourdomain.com"
route53_zone_id = "ZXXXXXXXXXXXXX"

# Sentry version
sentry_version = "26.4.2"

# Admin account — change these
sentry_admin_email    = "admin@yourdomain.com"
sentry_admin_password = "CHANGE_ME_STRONG_PASSWORD"

# SMTP — optional, remove if you don't need email notifications
smtp_host     = "smtp.gmail.com"
smtp_port     = 587
smtp_user     = "noreply@yourdomain.com"
smtp_password = "CHANGE_ME_APP_PASSWORD"
smtp_use_tls  = true

# Security — restrict SSH to your office/VPN IP in production
ssh_allowed_cidr_blocks = ["YOUR_OFFICE_IP/32"]
allowed_cidr_blocks     = ["0.0.0.0/0"]

# Optional: set to the Laravel server's private IP /32 so Sentry relay
# can be reached on port 3000 directly (avoids going through the internet)
laravel_server_cidr = ""
