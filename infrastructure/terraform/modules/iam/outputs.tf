output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node_group.arn
}

output "github_actions_role_arn" {
  value       = var.enable_github_oidc ? aws_iam_role.github_actions_ecr_push[0].arn : null
  description = "Set as the AWS role in Phase 7's GitHub Actions workflow (aws-actions/configure-aws-credentials)"
}
