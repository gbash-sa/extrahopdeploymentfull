variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lab"
}

variable "default_tags" {
  description = "Default tags"
  type        = map(string)
  default = {
    Project   = "ExtraHop-Lab"
    ManagedBy = "Terraform"
  }
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default = {
    Environment = "lab"
    Purpose     = "testing"
  }
}