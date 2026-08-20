output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description = "Used by the RDS module to allow inbound Postgres traffic only from EKS nodes"
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "Referenced by IRSA roles created in later phases (AWS Load Balancer Controller, Cluster Autoscaler, External Secrets Operator)"
}

output "oidc_provider_url" {
  value = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "node_group_name" {
  value = aws_eks_node_group.this.node_group_name
}
