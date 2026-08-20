variable "name" {
  description = "Name prefix for all resources (e.g. 'kubeforge-dev')"
  type        = string
}

variable "enable_github_oidc" {
  description = "Whether to create the GitHub Actions OIDC provider + role. Set false if this AWS account already has a GitHub OIDC provider (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization/username that owns the repo (used to scope the OIDC trust policy)"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name (used to scope the OIDC trust policy)"
  type        = string
  default     = ""
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the GitHub Actions role is allowed to push to"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource this module creates"
  type        = map(string)
  default     = {}
}
