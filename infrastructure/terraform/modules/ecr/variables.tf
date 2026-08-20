variable "repository_names" {
  description = "One ECR repository is created per name in this list"
  type        = list(string)
  default     = ["kubeforge-api", "kubeforge-worker", "kubeforge-frontend"]
}

variable "max_tagged_images_per_repo" {
  type    = number
  default = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
