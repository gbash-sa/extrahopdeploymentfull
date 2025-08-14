terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = var.default_tags
  }
}

# Get current AWS account and availability zones
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Create VPC for security account
resource "aws_vpc" "security" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(var.tags, {
    Name        = "${var.environment}-security-vpc"
    Environment = var.environment
    Purpose     = "security"
  })
}

# Create subnets
resource "aws_subnet" "security_private" {
  count             = 2
  vpc_id            = aws_vpc.security.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = merge(var.tags, {
    Name = "${var.environment}-security-private-${count.index + 1}"
    Type = "private"
  })
}

# Deploy cross-account roles
module "cross_account_roles" {
  source = "../../modules/cross-account-roles"
  
  environment = var.environment
  tags        = var.tags
}

# Deploy GWLB
module "gwlb" {
  source = "../../modules/gwlb"
  
  environment         = var.environment
  vpc_id              = aws_vpc.security.id
  subnet_ids          = aws_subnet.security_private[*].id
  allowed_account_ids = toset([data.aws_caller_identity.current.account_id])
  
  tags = var.tags
}

# Create KMS key for cross-account access
resource "aws_kms_key" "ndr_monitoring" {
  description             = "KMS key for NDR monitoring"
  multi_region            = true
  enable_key_rotation     = true
  deletion_window_in_days = 7  # Short for lab cleanup
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_kms_alias" "ndr_monitoring" {
  name          = "alias/${var.environment}-ndr-monitoring"
  target_key_id = aws_kms_key.ndr_monitoring.key_id
}

# Create ExtraHop API secret (placeholder for lab)
resource "aws_secretsmanager_secret" "extrahop_api" {
  name       = "${var.environment}-ndr-monitoring-api-secret"
  kms_key_id = aws_kms_key.ndr_monitoring.arn
  
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "extrahop_api" {
  secret_id = aws_secretsmanager_secret.extrahop_api.id
  secret_string = jsonencode({
    api_endpoint = "lab.api.extrahop.com"
    api_id       = "lab-api-id"
    api_secret   = "lab-api-secret"
  })
}