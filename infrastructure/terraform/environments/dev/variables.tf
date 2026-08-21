variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

# --- Networking ---
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "single_nat_gateway" {
  description = "true = 1 shared NAT Gateway. Cheapest option, single point of failure - acceptable for dev."
  type        = bool
  default     = true
}

# --- ECR ---
variable "ecr_repository_names" {
  type    = list(string)
  default = ["kubeforge-api", "kubeforge-worker", "kubeforge-frontend"]
}

variable "ecr_max_tagged_images" {
  type    = number
  default = 10 # dev doesn't need much history
}

# --- GitHub OIDC (Phase 7) ---
variable "enable_github_oidc" {
  type    = bool
  default = true
}

variable "github_org" {
  description = "Your GitHub username or org"
  type        = string
}

variable "github_repo" {
  description = "Repo name, e.g. 'kubeforge'"
  type        = string
  default     = "kubeforge"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID - only needed for repos using GitHub's immutable OIDC subject format. See modules/iam/variables.tf for how to find it."
  type        = string
  default     = ""
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID - see github_owner_id."
  type        = string
  default     = ""
}

# --- EKS ---
variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "eks_endpoint_public_access" {
  type    = bool
  default = true
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "eks_node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "eks_node_desired_size" {
  type    = number
  default = 2
}

variable "eks_node_min_size" {
  type    = number
  default = 1
}

variable "eks_node_max_size" {
  type    = number
  default = 3
}

# --- RDS ---
variable "rds_engine_version" {
  type    = string
  default = "16"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_allocated_storage" {
  type    = number
  default = 20
}

variable "rds_multi_az" {
  type    = bool
  default = false
}

variable "rds_backup_retention_period" {
  type    = number
  default = 1
}

variable "rds_deletion_protection" {
  type    = bool
  default = false
}

variable "rds_skip_final_snapshot" {
  type    = bool
  default = true
}

# --- S3 ---
variable "s3_expire_after_days" {
  description = "0 = never expire. Dev can afford a short TTL to keep costs near zero."
  type        = number
  default     = 30
}
