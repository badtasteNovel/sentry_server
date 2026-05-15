# ─────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────

data "aws_vpc" "selected" {
  id      = var.vpc_id != "" ? var.vpc_id : null
  default = var.vpc_id == ""
}

data "aws_subnets" "public" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

locals {
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.public[0].ids[0]
}

# Latest Ubuntu 22.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu" {
  count = var.ami_id == "" ? 1 : 0

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
}

# ─────────────────────────────────────────────
# SSH Key Pair
# ─────────────────────────────────────────────

resource "tls_private_key" "sentry" {
  count     = var.key_pair_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "sentry" {
  count      = var.key_pair_name == "" ? 1 : 0
  key_name   = "${var.project_name}-${var.environment}-key"
  public_key = tls_private_key.sentry[0].public_key_openssh
}

resource "local_file" "private_key" {
  count           = var.key_pair_name == "" ? 1 : 0
  content         = tls_private_key.sentry[0].private_key_pem
  filename        = "${path.module}/keys/${var.project_name}-${var.environment}.pem"
  file_permission = "0600"
}

locals {
  key_pair_name = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.sentry[0].key_name
}

# ─────────────────────────────────────────────
# Security Group
# ─────────────────────────────────────────────

module "security_group" {
  source = "./modules/security_group"

  name                    = "${var.project_name}-${var.environment}"
  vpc_id                  = data.aws_vpc.selected.id
  allowed_cidr_blocks     = var.allowed_cidr_blocks
  ssh_allowed_cidr_blocks = var.ssh_allowed_cidr_blocks
  laravel_server_cidr     = var.laravel_server_cidr
}

# ─────────────────────────────────────────────
# EC2 Instance + EBS Volumes
# ─────────────────────────────────────────────

module "ec2" {
  source = "./modules/ec2"

  name                = "${var.project_name}-${var.environment}"
  ami_id              = local.ami_id
  instance_type       = var.instance_type
  subnet_id           = local.subnet_id
  key_pair_name       = local.key_pair_name
  security_group_ids  = [module.security_group.id]
  root_volume_size_gb = var.root_volume_size_gb
  data_volume_size_gb = var.data_volume_size_gb

  user_data = templatefile("${path.module}/scripts/bootstrap.sh.tpl", {
    sentry_version        = var.sentry_version
    compose_profile       = var.compose_profile
    domain_name           = var.domain_name
    sentry_admin_email    = var.sentry_admin_email
    sentry_admin_password = var.sentry_admin_password
    smtp_host             = var.smtp_host
    smtp_port             = var.smtp_port
    smtp_user             = var.smtp_user
    smtp_password         = var.smtp_password
    smtp_use_tls          = var.smtp_use_tls
  })
}

# ─────────────────────────────────────────────
# Elastic IP
# ─────────────────────────────────────────────

resource "aws_eip" "sentry" {
  instance = module.ec2.instance_id
  domain   = "vpc"
}

# ─────────────────────────────────────────────
# DNS (Route53) — optional
# ─────────────────────────────────────────────

module "dns" {
  source = "./modules/dns"
  count  = var.route53_zone_id != "" ? 1 : 0

  zone_id     = var.route53_zone_id
  domain_name = var.domain_name
  public_ip   = aws_eip.sentry.public_ip
}
