variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_cluster_security_group_id" {
  description = "Only traffic from this security group (the EKS cluster) is allowed to reach Postgres"
  type        = string
}

variable "engine_version" {
  type    = string
  default = "16"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}

variable "db_name" {
  type    = string
  default = "kubeforge"
}

variable "master_username" {
  type    = string
  default = "kubeforge"
}

variable "multi_az" {
  description = "true for production (survives an AZ failure, costs ~2x). false for dev/staging."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to retain"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Blocks `terraform destroy` / console deletion. Should be true for production, false for dev so the environment stays genuinely disposable."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "true = terraform destroy deletes the data instantly (dev). false = a final snapshot is taken first (production)."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
