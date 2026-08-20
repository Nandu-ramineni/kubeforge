# IAM module: everything that does NOT depend on the EKS cluster existing yet.
# (The EKS cluster's own OIDC provider - needed for IRSA roles like the AWS
# Load Balancer Controller in Phase 6 - lives in the eks module instead,
# since it needs the cluster's OIDC issuer URL as an input.)

# --- EKS cluster role: what the EKS control plane itself assumes ---
resource "aws_iam_role" "eks_cluster" {
  name = "${var.name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- EKS node group role: what each worker node's kubelet assumes ---
resource "aws_iam_role" "eks_node_group" {
  name = "${var.name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# The three AWS-managed policies every EKS worker node needs, no more:
# - node lifecycle/networking operations against the EKS API
# - the CNI plugin's ability to attach/detach ENIs and IPs for pod networking
# - read-only ECR pull access, so nodes can pull our images without a
#   separate credential (kubelet's kubelet uses the node's own IAM role here)
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# --- GitHub Actions OIDC: lets CI (Phase 7) assume an AWS role to push to
# ECR with a short-lived token instead of a long-lived access key pair. ---
data "tls_certificate" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Fetched dynamically rather than hardcoded. GitHub has rotated this
  # certificate before (2023 - it broke every AWS account with a pinned
  # thumbprint when it happened), so pinning a static value here is exactly
  # the kind of thing that quietly breaks CI months from now for no reason
  # anyone will remember. Same pattern as the EKS OIDC provider in the eks
  # module, which already does this correctly.
  thumbprint_list = [data.tls_certificate.github_actions[0].certificates[0].sha1_fingerprint]

  tags = var.tags
}

resource "aws_iam_role" "github_actions_ecr_push" {
  count = var.enable_github_oidc ? 1 : 0

  name = "${var.name}-github-actions-ecr-push"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions[0].arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Scoped to this specific repo - any branch/tag/PR from
        # github_org/github_repo can assume this role, but nothing else can.
        # Tightened further to specific branches/environments in Phase 16.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = var.tags
}

# Least-privilege: push/pull to ECR only, nothing else. Explicitly NOT
# AdministratorAccess or PowerUserAccess - a compromised CI run can push a
# bad image, but cannot touch the VPC, IAM, RDS, or the cluster itself.
resource "aws_iam_role_policy" "github_actions_ecr_push" {
  count = var.enable_github_oidc ? 1 : 0

  name = "ecr-push"
  role = aws_iam_role.github_actions_ecr_push[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # GetAuthorizationToken does not support resource-level scoping
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}
