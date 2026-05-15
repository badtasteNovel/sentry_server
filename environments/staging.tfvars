# ─── staging.tfvars ───────────────────────────────────────────────────────────

aws_region  = "ap-southeast-1"
environment = "staging"

vpc_id    = ""
subnet_id = ""

# Cheaper instance for staging — still needs >= 8 GB for errors-only
instance_type       = "t3.large"
compose_profile     = "errors-only"
root_volume_size_gb = 60
data_volume_size_gb = 80

key_pair_name = ""

domain_name     = "sentry-staging.yourdomain.com"
route53_zone_id = "ZXXXXXXXXXXXXX"

sentry_version = "26.4.2"

sentry_admin_email    = "admin@yourdomain.com"
sentry_admin_password = "CHANGE_ME_STAGING_PASSWORD"

smtp_host     = ""
smtp_port     = 587
smtp_user     = ""
smtp_password = ""
smtp_use_tls  = true

ssh_allowed_cidr_blocks = ["0.0.0.0/0"]
allowed_cidr_blocks     = ["0.0.0.0/0"]
laravel_server_cidr     = ""
