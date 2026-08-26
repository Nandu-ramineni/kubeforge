# EKS module: the cluster itself, one managed node group, and the cluster's
# own OIDC provider. The OIDC provider is created HERE (not in the iam
# module) because it needs the cluster's issuer URL as an input - it can't
# exist before the cluster does. This is what Phase 6+ IRSA roles (AWS Load
# Balancer Controller, Cluster Autoscaler, External Secrets Operator) will
# attach to once those get installed - none of them exist yet, so no IRSA
# roles are created in this phase, just the provider they'll trust.

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    # Left open (0.0.0.0/0) when the public endpoint is enabled, which is the
    # simplest option for a portfolio project reachable from a laptop.
    # Production teams typically restrict this to an office/VPN CIDR or set
    # endpoint_public_access = false entirely and route through a bastion -
    # noted here rather than done, since it's a genuine environment-specific
    # trade-off, not a default either environment should get silently.
    public_access_cidrs = ["0.0.0.0/0"]
  }

  # Control plane audit/API logs to CloudWatch - the "who did what, when" the
  # SRE/incident-response phases will eventually query.
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = var.tags
}

# --- OIDC provider for IRSA (IAM Roles for Service Accounts) ---
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# --- Managed node group ---
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.private_subnet_ids # nodes never sit in public subnets

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  # The node group depends on the cluster policy attachment existing first -
  # Terraform can't infer this ordering from the resource graph alone since
  # the dependency is on IAM state outside this module.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # let the Autoscaler (Phase 10) own this after initial creation
  }
}

# EKS auto-creates a default vpc-cni add-on when the cluster is created,
# with NetworkPolicy enforcement OFF - confirmed via AWS's own announcement:
# "Starting with VPC CNI v1.14, NetworkPolicy support is available... but
# turned off by default at launch." This means every NetworkPolicy object
# this project has applied since Phase 9 has been syntactically valid and
# accepted by the API server, but never actually enforced by the data plane
# - a real gap, discovered while checking whether Phase 12's log collector
# would be blocked by them, not a hypothetical concern.
#
# resolve_conflicts_on_create = OVERWRITE is what lets Terraform "adopt"
# the add-on EKS already auto-created, rather than erroring the way the
# GitHub OIDC provider did back in Phase 5 (that resource has no equivalent
# adoption mechanism and needed a manual `terraform import` instead - this
# one is designed for exactly this situation).
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}
