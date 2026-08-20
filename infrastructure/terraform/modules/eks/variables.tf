variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version, e.g. '1.34'. Pinned rather than left to float, so cluster upgrades are always a deliberate, reviewed change."
  type        = string
  default     = "1.34"
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server is reachable from the public internet. true is simplest for a portfolio project; a real production cluster would typically set this false and access only via VPN/bastion."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is cheaper but nodes can be reclaimed with 2 minutes notice - fine for dev, riskier for production."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "tags" {
  type    = map(string)
  default = {}
}
