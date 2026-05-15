# CLAUDE.md — Sentry Self-Hosted Infrastructure

OpenTofu (Terraform-compatible) code that provisions a **dedicated AWS EC2 server** running Sentry self-hosted via docker-compose. This replaces Laravel Telescope in the `lg-laravel` Manufacturing Execution System (MES) project.

## What this repo does

- Provisions an EC2 instance (Ubuntu 22.04, `t3.xlarge`) with a separate EBS data volume.
- Runs a cloud-init bootstrap script that installs Docker, clones `getsentry/self-hosted`, configures Sentry, and starts it.
- Puts Nginx in front as a TLS-terminating reverse proxy (Let's Encrypt via certbot).
- Optionally creates a Route53 DNS A record pointing to the Elastic IP.
- All persistent data (Postgres, Redis, Kafka, ClickHouse) lives on the `/data` EBS volume so the EC2 instance can be replaced without data loss.

## Directory map

```
main.tf                 # Root composition — calls all modules
variables.tf            # All inputs (see below for key ones)
outputs.tf              # public_ip, sentry_url, ssh_command
providers.tf            # AWS provider + default tag block
versions.tf             # Version constraints + S3 backend config
Makefile                # make init / plan / apply / ssh / logs
modules/ec2/            # EC2 instance + root EBS + data EBS + attachment
modules/security_group/ # Ingress rules for 80, 443, 22, optional relay port 3000
modules/dns/            # Route53 A record (count=0 when route53_zone_id is empty)
scripts/bootstrap.sh.tpl  # Bash template rendered by templatefile() — runs on first boot
config/laravel-sentry.env.example  # .env snippet for the Laravel project
environments/production.tfvars
environments/staging.tfvars
```

## Key variables

| Variable | Default | Notes |
|----------|---------|-------|
| `aws_region` | `ap-southeast-1` | Singapore — same region as lg-laravel |
| `instance_type` | `t3.xlarge` | 4 vCPU, 16 GB RAM. Minimum for errors-only profile. |
| `compose_profile` | `errors-only` | `feature-complete` needs 16 GB RAM (t3.2xlarge) |
| `sentry_version` | `26.4.2` | Match a tag from getsentry/self-hosted releases |
| `domain_name` | required | e.g. `sentry.yourdomain.com` |
| `route53_zone_id` | `""` (skip DNS) | Set to create DNS record automatically |
| `laravel_server_cidr` | `""` | Set to Laravel server private IP /32 to open relay port 3000 directly |
| `data_volume_size_gb` | `200` | EBS gp3 volume mounted at `/data` |

## Common tasks

### First-time deploy
```bash
make init
# Edit environments/production.tfvars (or a .local copy)
make plan ENV=production
make apply ENV=production
```

### Watch bootstrap progress
```bash
make logs ENV=production   # streams sentry systemd logs via SSH
# or on the server:
sudo tail -f /var/log/sentry-bootstrap.log
```

### Upgrade Sentry version
Update `sentry_version` in tfvars but do NOT re-apply tofu (user_data changes are ignored by `lifecycle.ignore_changes` to prevent destroy/recreate). Instead SSH in:
```bash
cd /opt/sentry
git fetch --tags && git checkout <new-version>
docker compose pull
bash install.sh --skip-user-creation --no-user-prompt
systemctl restart sentry
```

### Resize the instance
```bash
# Edit instance_type in tfvars, then:
make apply ENV=production
# tofu will stop → resize → start the instance in-place
```

### SSH into the server
```bash
make ssh ENV=production
```

## Architecture decisions

- **EC2 not K8s** — Sentry self-hosted is officially docker-compose based. Running it inside the existing lg-laravel K8s cluster would require significant customization and StatefulSet management for Kafka/ClickHouse. A dedicated VM is simpler to operate and matches the Sentry team's supported deployment model.

- **errors-only compose profile** — The full `feature-complete` profile requires 16 GB RAM and adds replays, profiling, and metrics consumers. For a factory MES replacing Telescope, error tracking is the primary need. Switch to `feature-complete` by changing `instance_type` to `t3.2xlarge` and `compose_profile` to `feature-complete`.

- **Separate EBS data volume** — The root volume is ephemeral from an operational standpoint. Postgres, Redis, Kafka, and ClickHouse data directories are bind-mounted from the `/data` EBS volume (200 GB gp3). This means you can terminate and recreate the EC2 instance without losing Sentry history.

- **`user_data_replace_on_change = false`** — Prevents tofu from destroying and recreating the EC2 instance if the bootstrap script is edited after initial deploy. The script only runs once on first boot anyway.

- **Nginx in front of Sentry** — Sentry's docker-compose exposes port 9000 on localhost. Nginx terminates TLS, handles Let's Encrypt renewals, and keeps the EIP security group rules simple (80/443 only).

## What NOT to do

- Do not run `make destroy` without taking an EBS snapshot first. The data volume is deleted on destroy.
- Do not change `user_data_replace_on_change = true` — this would cause the instance to be destroyed and recreated on any bootstrap script edit, losing data if the EBS volume is somehow not reattached correctly.
- Do not store real passwords in `environments/*.tfvars` files that are committed to git. Use a `.local` copy (gitignored) or pass via environment variables: `TF_VAR_sentry_admin_password=...`.
- Do not set `ssh_allowed_cidr_blocks = ["0.0.0.0/0"]` in production. Restrict to your office/VPN CIDR.

## Connecting to lg-laravel

After deploying, get the DSN from Sentry UI → Settings → Projects → \<project\> → Client Keys.

Add to `lg-laravel/.env`:
```ini
SENTRY_LARAVEL_DSN=https://<key>@sentry.yourdomain.com/<project-id>
SENTRY_TRACES_SAMPLE_RATE=0.1
```

Install the SDK: `composer require sentry/sentry-laravel`
Then remove Telescope: `composer remove laravel/telescope`

See `config/laravel-sentry.env.example` for the full `.env` snippet.
