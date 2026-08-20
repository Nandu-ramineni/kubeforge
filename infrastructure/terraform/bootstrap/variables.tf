variable "aws_region" {
  description = "AWS region the state bucket lives in"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. Must be changed from the default - S3 bucket names are global across ALL AWS accounts."
  type        = string
}
