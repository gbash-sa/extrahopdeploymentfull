terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = var.common_tags
  }
}

# Data sources for existing infrastructure
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "existing" {
  for_each = toset(data.aws_subnets.existing.ids)
  id       = each.value
}

# Get private subnets for ExtraHop sensors
locals {
  private_subnets = [
    for subnet in data.aws_subnet.existing : subnet.id
    if !subnet.map_public_ip_on_launch
  ]
  
  # Use first two private subnets, or create in public if no private subnets
  sensor_subnets = length(local.private_subnets) >= 2 ? slice(local.private_subnets, 0, 2) : slice(data.aws_subnets.existing.ids, 0, 2)
  
  # Use first subnet for VPC endpoints
  endpoint_subnets = [data.aws_subnets.existing.ids[0]]
}

# Create IAM role for Lambda functions
module "cross_account_roles" {
  source = "./modules/cross-account-roles"
  
  environment = var.environment
  tags        = var.common_tags
}

# Security group for ExtraHop sensors
resource "aws_security_group" "extrahop_management" {
  name        = "${var.environment}-extrahop-management"
  description = "Security group for ExtraHop sensor management"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "SSH access"
  }

  # HTTPS management
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "HTTPS management"
  }

  # Key forwarder
  ingress {
    from_port   = 4873
    to_port     = 4873
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
    description = "Key forwarder"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-extrahop-management-sg"
  })
}

resource "aws_security_group" "extrahop_capture" {
  name        = "${var.environment}-extrahop-capture"
  description = "Security group for ExtraHop sensor capture interface"
  vpc_id      = var.vpc_id

  # GENEVE traffic from GWLB
  ingress {
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
    description = "GENEVE from GWLB"
  }

  # Health check traffic
  ingress {
    from_port   = 2003
    to_port     = 2010
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
    description = "Health check traffic"
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-extrahop-capture-sg"
  })
}

# Create Network Interfaces for ExtraHop sensors
resource "aws_network_interface" "extrahop_management" {
  count           = var.extrahop_sensor_count
  subnet_id       = local.sensor_subnets[count.index % length(local.sensor_subnets)]
  security_groups = [aws_security_group.extrahop_management.id]
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-extrahop-mgmt-${count.index + 1}"
  })
}

resource "aws_network_interface" "extrahop_capture" {
  count           = var.extrahop_sensor_count
  subnet_id       = local.sensor_subnets[count.index % length(local.sensor_subnets)]
  security_groups = [aws_security_group.extrahop_capture.id]
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-extrahop-capture-${count.index + 1}"
  })
}

# ExtraHop sensor instances
resource "aws_instance" "extrahop" {
  count = var.extrahop_sensor_count

  ami           = var.extrahop_ami_id
  instance_type = var.extrahop_instance_type
  key_name      = var.key_pair_name

  # Management interface (device_index = 0)
  network_interface {
    network_interface_id = aws_network_interface.extrahop_management[count.index].id
    device_index         = 0
  }

  # Capture interface (device_index = 1)
  network_interface {
    network_interface_id = aws_network_interface.extrahop_capture[count.index].id
    device_index         = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.extrahop_storage_size
    encrypted   = true
  }

  # Additional storage for packet capture
  ebs_block_device {
    device_name = "/dev/sdb"
    volume_type = "gp3"
    volume_size = var.extrahop_ppcap_storage_size
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-extrahop-sensor-${count.index + 1}"
    Role = "ExtraHop-Sensor"
  })
}

# Deploy GWLB module
module "gwlb" {
  source = "./modules/gwlb"
  
  environment         = var.environment
  vpc_id              = var.vpc_id
  subnet_ids          = local.sensor_subnets
  allowed_account_ids = toset([data.aws_caller_identity.current.account_id])
  
  tags = var.common_tags
}

# Target group attachments for ExtraHop capture interfaces
resource "aws_lb_target_group_attachment" "extrahop" {
  count            = var.extrahop_sensor_count
  target_group_arn = module.gwlb.target_group_arn
  target_id        = aws_network_interface.extrahop_capture[count.index].private_ip
}

# Create secrets for ExtraHop API
resource "aws_secretsmanager_secret" "extrahop_api" {
  name        = "${var.environment}-ndr-monitoring-api-secret"
  description = "ExtraHop API credentials for NDR monitoring"
  
  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "extrahop_api" {
  secret_id = aws_secretsmanager_secret.extrahop_api.id
  secret_string = jsonencode({
    api_endpoint = var.extrahop_api_endpoint
    api_id       = var.extrahop_api_id
    api_secret   = var.extrahop_api_secret
  })
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Deploy traffic mirroring module
module "traffic_mirroring" {
  source = "./modules/traffic-mirroring"
  
  environment          = var.environment
  vpc_id               = var.vpc_id
  region               = var.aws_region
  gwlb_service_name    = module.gwlb.endpoint_service_name
  endpoint_subnet_ids  = local.endpoint_subnets
  lambda_role_arn      = module.cross_account_roles.ndr_monitoring_role_arn
  api_secret_arn       = aws_secretsmanager_secret.extrahop_api.arn
  mirror_tag_key       = var.mirror_tag_key
  mirror_tag_values    = var.mirror_tag_values
  
  environment_tags = {
    "tag_Environment" = var.environment
    "tag_Project"     = var.common_tags.Project
    "tag_ManagedBy"   = var.common_tags.ManagedBy
  }
  
  tags = var.common_tags
}

# Test instances with traffic mirroring tags
resource "aws_instance" "test_instances" {
  count = var.create_test_instances ? var.test_instance_count : 0

  ami                    = var.test_instance_ami_id != "" ? var.test_instance_ami_id : data.aws_ami.amazon_linux.id
  instance_type          = var.test_instance_type
  key_name               = var.key_pair_name
  subnet_id              = local.sensor_subnets[count.index % length(local.sensor_subnets)]
  vpc_security_group_ids = [aws_security_group.test_instances[0].id]

  tags = merge(var.common_tags, {
    Name                     = "${var.environment}-test-instance-${count.index + 1}"
    "${var.mirror_tag_key}" = var.mirror_tag_values[0]
    Purpose                 = "testing"
    TestInstance            = "true"
  })
}

# Security group for test instances
resource "aws_security_group" "test_instances" {
  count = var.create_test_instances ? 1 : 0
  
  name        = "${var.environment}-test-instances"
  description = "Security group for test instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "SSH access"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
    description = "HTTP traffic for testing"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-test-instances-sg"
  })
}

# Get latest Amazon Linux 2 AMI for test instances
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}