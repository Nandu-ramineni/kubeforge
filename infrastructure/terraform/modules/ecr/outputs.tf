output "repository_urls" {
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
  description = "Map of repo name -> full push/pull URL, used in Phase 7's CI workflow"
}

output "repository_arns" {
  value = [for repo in aws_ecr_repository.this : repo.arn]
}
