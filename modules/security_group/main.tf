resource "aws_security_group" "sentry" {
  name        = "${var.name}-sg"
  description = "Sentry self-hosted security group"
  vpc_id      = var.vpc_id

  # HTTP — Let's Encrypt + redirect
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS — Sentry web UI + DSN ingest
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SSH — restricted
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Optional: allow the Laravel server to reach Sentry relay port directly
resource "aws_security_group_rule" "laravel_ingest" {
  count = var.laravel_server_cidr != "" ? 1 : 0

  type              = "ingress"
  description       = "Laravel server → Sentry relay ingest"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = [var.laravel_server_cidr]
  security_group_id = aws_security_group.sentry.id
}
