terraform {
  backend "s3" {
    bucket       = "kubeforge"
    key          = "staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
