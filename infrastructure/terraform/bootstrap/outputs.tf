output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Use this as the 'bucket' value in every environments/*/backend.tf"
}
