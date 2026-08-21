output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
  description = "Needed when creating IRSA roles for cluster addons in Phase 6+"
}

output "aws_lb_controller_role_arn" {
  value       = module.irsa_aws_lb_controller.role_arn
  description = "Set as eks.amazonaws.com/role-arn on the aws-load-balancer-controller ServiceAccount when installing via Helm"
}

output "cluster_autoscaler_role_arn" {
  value       = module.irsa_cluster_autoscaler.role_arn
  description = "Set as eks.amazonaws.com/role-arn on the cluster-autoscaler ServiceAccount when installing via Helm"
}

output "vpc_id_for_lb_controller" {
  value       = module.vpc.vpc_id
  description = "Passed as --set vpcId=... in the AWS Load Balancer Controller Helm install"
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "rds_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "rds_db_name" {
  value = module.rds.db_name
}

output "rds_master_username" {
  value = module.rds.master_username
}

output "rds_master_user_secret_arn" {
  value       = module.rds.master_user_secret_arn
  description = "Secrets Manager ARN - fetch the actual password with: aws secretsmanager get-secret-value --secret-id <this-arn>"
}

output "github_actions_role_arn" {
  value       = module.iam.github_actions_role_arn
  description = "Set as AWS_ROLE_ARN in the Phase 7 GitHub Actions workflow"
}

output "s3_app_bucket" {
  value = module.s3.bucket_name
}

output "configure_kubectl" {
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
  description = "Run this after apply to point kubectl at the real cluster"
}
