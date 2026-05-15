output "instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2.instance_id
}

output "public_ip" {
  description = "Elastic IP assigned to the Sentry server"
  value       = aws_eip.sentry.public_ip
}

output "sentry_url" {
  description = "Sentry web URL"
  value       = "https://${var.domain_name}"
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i keys/${var.project_name}-${var.environment}.pem ubuntu@${aws_eip.sentry.public_ip}"
}

output "private_key_path" {
  description = "Path to the generated SSH private key (only when key_pair_name is not set)"
  value       = var.key_pair_name == "" ? "${path.module}/keys/${var.project_name}-${var.environment}.pem" : "using existing key pair: ${var.key_pair_name}"
}

output "laravel_dsn_note" {
  description = "Where to find your Laravel project DSN after first login"
  value       = "Log in at https://${var.domain_name} → Settings → Projects → <your project> → Client Keys (DSN)"
}
