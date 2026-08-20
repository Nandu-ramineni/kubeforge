variable "bucket_name" {
  type = string
}

variable "versioning_enabled" {
  type    = bool
  default = true
}

variable "expire_after_days" {
  description = "Objects older than this are auto-deleted. 0 disables expiration entirely (production DR backups should generally NOT expire on a short window)."
  type        = number
  default     = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
