variable "name" {
  description = "IAM role name, e.g. 'kubeforge-dev-aws-lb-controller'"
  type        = string
}

variable "oidc_provider_arn" {
  description = "From module.eks.oidc_provider_arn"
  type        = string
}

variable "oidc_provider_url" {
  description = "From module.eks.oidc_provider_url (no https:// prefix)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the ServiceAccount lives in"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount name this role is scoped to"
  type        = string
}

variable "policy_arn" {
  description = "An existing AWS-managed or customer-managed policy ARN to attach. Mutually exclusive with policy_json in practice, but both can technically be set if actually needed."
  type        = string
  default     = null
}

variable "policy_json" {
  description = "Inline policy JSON (e.g. from file(\"policy.json\")) to attach directly to this role."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
