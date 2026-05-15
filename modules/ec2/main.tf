resource "aws_instance" "sentry" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.key_pair_name
  vpc_security_group_ids = var.security_group_ids

  # User data runs once on first boot to install Docker + Sentry
  user_data                   = var.user_data
  user_data_replace_on_change = false # prevent destroy/recreate on script edits

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    throughput            = 125
    iops                  = 3000
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    ignore_changes = [
      # AMI may be updated; don't recreate the instance automatically
      ami,
      user_data,
    ]
  }
}

# Separate EBS data volume — survives instance replacement
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.sentry.availability_zone
  size              = var.data_volume_size_gb
  type              = "gp3"
  throughput        = 250
  iops              = 4000
  encrypted         = true

  tags = {
    Name = "${var.name}-data"
  }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.sentry.id
  force_detach = false
}
