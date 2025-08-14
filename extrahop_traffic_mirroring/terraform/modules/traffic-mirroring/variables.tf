variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where traffic mirroring will be deployed"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "gwlb_service_name" {
  description = "GWLB endpoint service name"
  type        = string
}

variable "endpoint_subnet_ids" {
  description = "Subnet IDs for VPC endpoints"
  type        = list(string)
}

variable "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  type        = string
}

variable "api_secret_arn" {
  description = "ARN of the ExtraHop API secret"
  type        = string
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

variable "environment_tags" {
  description = "Environment variables as tags for Lambda functions"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}