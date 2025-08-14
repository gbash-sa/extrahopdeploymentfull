variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (lab, dev, prod, etc.)"
  type        = string
  default     = "lab"
}

variable "vpc_id" {
  description = "Existing VPC ID to deploy ExtraHop sensors"
  type        = string
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

variable "extrahop_sensor_count" {
  description = "Number of ExtraHop sensors to deploy"
  type        = number
  default     = 2
}

variable "extrahop_storage_size" {
  description = "Root volume size for ExtraHop sensors (GB)"
  type        = number
  default     = 100
}

variable "extrahop_ppcap_storage_size" {
  description = "Packet capture storage size (GB)"
  type        = number
  default     = 500
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for instance access"
  type        = string
}

variable "allowed_cidr" {
  description = "CIDR allowed for SSH/HTTPS access to sensors"
  type        = string
  default     = "10.0.0.0/8"
}

# ExtraHop API Configuration
variable "extrahop_api_endpoint" {
  description = "ExtraHop API endpoint (e.g., company.api.extrahop.com)"
  type        = string
  default     = "lab.api.extrahop.com"
}

variable "extrahop_api_id" {
  description = "ExtraHop API ID"
  type        = string
  default     = "lab-api-id"
}

variable "extrahop_api_secret" {
  description = "ExtraHop API secret"
  type        = string
  default     = "lab-api-secret"
  sensitive   = true
}

# Traffic Mirroring Tag Configuration
variable "mirror_tag_key" {
  description = "Tag key to identify instances for traffic mirroring"
  type        = string
  default     = "TrafficMirror"
}

variable "mirror_tag_values" {
  description = "Tag values that enable traffic mirroring"
  type        = list(string)
  default     = ["enabled", "true"]
}

# Test Instance Configuration
variable "create_test_instances" {
  description = "Whether to create test instances for validation"
  type        = bool
  default     = true
}

variable "test_instance_count" {
  description = "Number of test instances to create"
  type        = number
  default     = 2
}

variable "test_instance_type" {
  description = "Instance type for test instances"
  type        = string
  default     = "t3.micro"
}

variable "test_instance_ami_id" {
  description = "AMI ID for test instances (leave empty for latest Amazon Linux 2)"
  type        = string
  default     = ""
}

# Common tags
variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "ExtraHop-Traffic-Mirroring"
    ManagedBy = "Terraform"
  }
}