variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the target group"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the GWLB"
  type        = list(string)
}

variable "allowed_account_ids" {
  description = "Set of AWS account IDs allowed to use the endpoint service"
  type        = set(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}