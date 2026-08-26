locals {
  name = "kubeforge-${var.environment}"

  common_tags = {
    Project     = "kubeforge"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names           = var.ecr_repository_names
  max_tagged_images_per_repo = var.ecr_max_tagged_images
  tags                       = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  name                = local.name
  enable_github_oidc  = var.enable_github_oidc
  github_org          = var.github_org
  github_repo         = var.github_repo
  github_owner_id     = var.github_owner_id
  github_repo_id      = var.github_repo_id
  ecr_repository_arns = module.ecr.repository_arns
  tags                = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.name
  kubernetes_version     = var.kubernetes_version
  cluster_role_arn       = module.iam.eks_cluster_role_arn
  node_role_arn          = module.iam.eks_node_role_arn
  private_subnet_ids     = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  endpoint_public_access = var.eks_endpoint_public_access
  node_instance_types    = var.eks_node_instance_types
  node_capacity_type     = var.eks_node_capacity_type
  node_desired_size      = var.eks_node_desired_size
  node_min_size          = var.eks_node_min_size
  node_max_size          = var.eks_node_max_size
  tags                   = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  name                           = local.name
  vpc_id                         = module.vpc.vpc_id
  private_subnet_ids             = module.vpc.private_subnet_ids
  eks_cluster_security_group_id  = module.eks.cluster_security_group_id
  engine_version                 = var.rds_engine_version
  instance_class                 = var.rds_instance_class
  allocated_storage              = var.rds_allocated_storage
  multi_az                       = var.rds_multi_az
  backup_retention_period        = var.rds_backup_retention_period
  deletion_protection            = var.rds_deletion_protection
  skip_final_snapshot            = var.rds_skip_final_snapshot
  tags                           = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  bucket_name        = "${local.name}-app-${data.aws_caller_identity.current.account_id}"
  versioning_enabled = true
  expire_after_days  = var.s3_expire_after_days
  tags               = local.common_tags
}

# --- AWS Load Balancer Controller IRSA role ---
# The controller itself is installed via Helm (Phase 6 documentation, not
# Terraform - it's a cluster addon, not infrastructure) but the IAM role it
# needs to actually create/manage ALBs on your behalf has to exist first,
# and that's IAM, so it belongs here. The policy JSON is fetched verbatim
# from the upstream project (policies/aws-load-balancer-controller-policy.json)
# rather than hand-copied, so it stays exactly in sync with what the
# controller's own documentation specifies.
module "irsa_aws_lb_controller" {
  source = "../../modules/irsa"

  name                 = "${local.name}-aws-lb-controller"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  policy_json          = file("${path.module}/policies/aws-load-balancer-controller-policy.json")
  tags                 = local.common_tags
}

# Cluster Autoscaler IRSA role. Note what's NOT here: any tagging of the EKS
# node group's underlying Auto Scaling Group. AWS's own docs confirm managed
# node groups are automatically tagged for Cluster Autoscaler discovery the
# moment they're created (k8s.io/cluster-autoscaler/enabled,
# k8s.io/cluster-autoscaler/<cluster-name>) - checked this specifically
# rather than assume, since it directly determines whether this phase needed
# any changes to modules/eks at all. It didn't - only this IAM role, for the
# Cluster Autoscaler POD itself to have permission to call the ASG/EC2 APIs.
module "irsa_cluster_autoscaler" {
  source = "../../modules/irsa"

  name                 = "${local.name}-cluster-autoscaler"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "cluster-autoscaler"
  policy_json = templatefile("${path.module}/policies/cluster-autoscaler-policy.json", {
    cluster_name = local.name
  })
  tags = local.common_tags
}

# EBS CSI driver - confirmed the hard way, in Phase 12, that this cluster
# had NO default StorageClass at all: every phase up to this point only
# ever needed RDS, Redis, or ephemeral storage, so the gap went unnoticed
# until Loki's PVC got stuck permanently Pending with "pod has unbound
# immediate PersistentVolumeClaims. not found". Unlike modules/eks's
# vpc_cni addon, this one genuinely needs its own IRSA role - the node
# role alone isn't sufficient/appropriate for EC2 volume management
# permissions (CreateVolume, AttachVolume, DeleteVolume), and scoping
# that to a dedicated role instead of broadening the shared node role
# matches the least-privilege pattern used for every other addon so far.
# AWS publishes an official managed policy for this one, unlike Cluster
# Autoscaler's custom policy above.
module "irsa_ebs_csi_driver" {
  source = "../../modules/irsa"

  name                 = "${local.name}-ebs-csi-driver"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  # This exact service account name is fixed by the EBS CSI driver itself,
  # not a name we chose - both the EKS-addon and Helm-chart install methods
  # use this same, unchanging convention.
  service_account_name = "ebs-csi-controller-sa"
  policy_arn           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  tags                 = local.common_tags
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name              = module.eks.cluster_name
  addon_name                = "aws-ebs-csi-driver"
  service_account_role_arn  = module.irsa_ebs_csi_driver.role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

# S3 bucket names are globally unique across ALL AWS accounts - suffixing
# with the account ID avoids a name collision with someone else's bucket
# without you having to hand-pick a unique name yourself.
data "aws_caller_identity" "current" {}
