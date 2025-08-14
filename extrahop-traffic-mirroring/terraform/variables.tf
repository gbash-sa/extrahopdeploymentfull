# terraform/variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_id" {
  description = "Existing VPC ID (leave empty to create new VPC)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR block (only used if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "extrahop_ami_id" {
  description = "ExtraHop AMI ID from AWS Marketplace"
  type        = string
}

variable "extrahop_instance_type" {
  description = "Instance type for ExtraHop sensors"
  type        = string
  default     = "m5.xlarge"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR allowed for SSH/HTTPS access"
  type        = string
  default     = "10.0.0.0/8"
}

variable "mirror_tag_key" {
  description = "Tag key to identify instances for mirroring"
  type        = string
  default     = "TrafficMirror"
}

variable "mirror_tag_values" {
  description = "Tag values that enable mirroring"
  type        = list(string)
  default     = ["enabled", "true"]
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "ExtraHop-Traffic-Mirroring"
    ManagedBy = "Terraform"
  }
}