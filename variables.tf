variable "aws_region" {
  description = "AWS region to deploy Sentry into"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Deployment environment (production, staging)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging"], var.environment)
    error_message = "Must be 'production' or 'staging'."
  }
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "sentry"
}

# --- Networking ---

variable "vpc_id" {
  description = "VPC ID to deploy Sentry into. Leave empty to use the default VPC."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for the Sentry EC2 instance. Must be a public subnet."
  type        = string
  default     = ""
}

# --- EC2 ---

variable "instance_type" {
  description = "EC2 instance type. Sentry self-hosted needs >= 8 GB RAM (t3.xlarge) for full profile, or 4 GB (t3.large) for errors-only profile."
  type        = string
  default     = "t3.xlarge"
}

variable "compose_profile" {
  description = "Sentry compose profile: 'feature-complete' (requires 16 GB RAM) or 'errors-only' (requires 8 GB RAM)"
  type        = string
  default     = "errors-only"

  validation {
    condition     = contains(["feature-complete", "errors-only"], var.compose_profile)
    error_message = "Must be 'feature-complete' or 'errors-only'."
  }
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID. Leave empty to auto-select the latest for the region."
  type        = string
  default     = ""
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 100
}

variable "data_volume_size_gb" {
  description = "Separate EBS data volume size in GB (PostgreSQL + Redis + uploads)"
  type        = number
  default     = 200
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH access. Leave empty to generate a new one."
  type        = string
  default     = ""
}

# --- DNS ---

variable "domain_name" {
  description = "Domain name for Sentry (e.g. sentry.example.com)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain. Leave empty to skip DNS record creation."
  type        = string
  default     = ""
}

# --- Sentry ---

variable "sentry_version" {
  description = "Sentry self-hosted version tag to deploy"
  type        = string
  default     = "26.4.2"
}

variable "sentry_admin_email" {
  description = "Sentry superuser email address"
  type        = string
}

variable "sentry_admin_password" {
  description = "Sentry superuser password"
  type        = string
  sensitive   = true
}

variable "smtp_host" {
  description = "SMTP host for Sentry outbound email"
  type        = string
  default     = ""
}

variable "smtp_port" {
  description = "SMTP port"
  type        = number
  default     = 587
}

variable "smtp_user" {
  description = "SMTP username"
  type        = string
  default     = ""
}

variable "smtp_password" {
  description = "SMTP password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "smtp_use_tls" {
  description = "Use TLS for SMTP"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Sentry on port 80/443. Default allows all."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidr_blocks" {
  description = "CIDR blocks allowed SSH access (port 22). Restrict in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "laravel_server_cidr" {
  description = "CIDR of the existing Laravel server so it can reach Sentry on port 9000 directly (DSN ingest). Usually the Laravel EC2 private IP /32."
  type        = string
  default     = ""
}
