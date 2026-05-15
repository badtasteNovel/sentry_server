output "instance_id" {
  value = aws_instance.sentry.id
}

output "private_ip" {
  value = aws_instance.sentry.private_ip
}

output "availability_zone" {
  value = aws_instance.sentry.availability_zone
}
