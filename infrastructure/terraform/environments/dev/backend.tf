# Backend blocks cannot reference variables (a Terraform limitation - the
# backend has to be known before any variables are evaluated), so these
# values are hardcoded per environment on purpose. Replace the bucket name
# with the one bootstrap/ actually created for you.
terraform {
  backend "s3" {
    bucket       = "kubeforge"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking (Terraform 1.11+) - no DynamoDB table needed
  }
}
