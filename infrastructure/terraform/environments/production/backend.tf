terraform {
  backend "s3" {
    bucket       = "kubeforge"
    key          = "production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
