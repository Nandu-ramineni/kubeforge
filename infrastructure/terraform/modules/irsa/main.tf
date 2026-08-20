# Generic IRSA (IAM Roles for Service Accounts) module. Every Kubernetes
# addon that needs to call AWS APIs - the AWS Load Balancer Controller now,
# Cluster Autoscaler and External Secrets Operator in later phases - needs
# the exact same shape of thing: an IAM role that trusts the EKS cluster's
# OIDC provider, scoped to one specific namespace + ServiceAccount, with some
# policy attached. Rather than repeat that trust-policy boilerplate for each
# addon, this module takes the varying parts (name, service account,
# permissions) and handles the rest once.

resource "aws_iam_role" "this" {
  name = var.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          # This is the actual scoping mechanism: only a pod running under
          # this exact namespace + service account name can assume this
          # role, not just any pod in the cluster.
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  count = var.policy_arn != null ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = var.policy_arn
}

resource "aws_iam_role_policy" "inline" {
  count = var.policy_json != null ? 1 : 0

  name   = "${var.name}-policy"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}
