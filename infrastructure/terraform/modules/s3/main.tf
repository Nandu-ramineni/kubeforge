# S3 module: an application-level bucket - database backup exports for the
# Disaster Recovery phase, and any static assets later. This is intentionally
# separate from infrastructure/terraform/bootstrap's state bucket - mixing
# "Terraform's own state" with "things the app writes to" in one bucket is a
# blast-radius mistake (an app bug or an overly broad IAM policy could touch
# infrastructure state, or a state bucket policy change could break the app).

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.expire_after_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-objects"
    status = "Enabled"

    filter {} # applies to every object in the bucket

    expiration {
      days = var.expire_after_days
    }
  }
}
