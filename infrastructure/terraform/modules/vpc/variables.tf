variable "name" {
  description = "Name prefix for all resources in this VPC (e.g. 'kubeforge-dev')"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (cheap, single point of failure - dev/staging). false = one NAT Gateway per AZ (resilient, costs more - production)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource this module creates"
  type        = map(string)
  default     = {}
}
