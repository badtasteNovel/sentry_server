provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "sentry"
      Environment = var.environment
      ManagedBy   = "opentofu"
    }
  }
}
