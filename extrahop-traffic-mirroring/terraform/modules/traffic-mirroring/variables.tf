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