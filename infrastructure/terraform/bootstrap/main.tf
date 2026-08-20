# Bootstrap: creates the S3 bucket that every environment's remote state
# lives in. This CANNOT be part of the environments/* configs themselves -
# Terraform can't use a backend that doesn't exist yet to create that same
# backend (chicken-and-egg). So this one config runs with local state, once,
# by hand, before anything else:
#
#   cd infrastructure/terraform/bootstrap
#   terraform init
#   terraform apply
#
# After that, this bucket is never touched by any other Terraform config -
# environments/*/backend.tf just points AT it.

terraform {
  required_version = ">= 1.11.0" # required for native S3 state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Deliberately local state for this one config - see comment above.
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Prevents `terraform destroy` (run against the wrong config, by accident)
  # from deleting the bucket every other environment's state lives in.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = "kubeforge"
    ManagedBy = "terraform"
    Purpose   = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled" # lets a bad apply's state be rolled back to the previous version
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No DynamoDB table here on purpose - Terraform's S3 backend has supported
# native state locking (use_lockfile = true) since 1.11, so a separate lock
# table is no longer needed. Each environment's backend.tf uses this.
