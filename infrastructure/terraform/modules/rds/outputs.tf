output "db_instance_endpoint" {
  value       = aws_db_instance.this.endpoint
  description = "host:port - combine with the secret below to build DATABASE_URL"
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_username" {
  value = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
  description = "AWS Secrets Manager ARN holding the auto-generated master password. This is what External Secrets Operator points at - never a Terraform variable."
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
