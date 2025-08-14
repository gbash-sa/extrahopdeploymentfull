# terraform/main.tf
terraform {
  required_version = ">= 1.0"
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

# Get existing VPC or create new one
data "aws_vpc" "existing" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Use existing VPC or create basic infrastructure
locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : aws_vpc.main[0].id
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Create VPC if not provided
resource "aws_vpc" "main" {
  count = var.vpc_id == "" ? 1 : 0
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(var.common_tags, {
    Name = "extrahop-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count = var.vpc_id == "" ? 1 : 0
  
  vpc_id = local.vpc_id
  
  tags = merge(var.common_tags, {
    Name = "extrahop-igw"
  })
}

# Public Subnets for ExtraHop management and GWLB endpoints
resource "aws_subnet" "public" {
  count = length(local.availability_zones)
  
  vpc_id                  = local.vpc_id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(var.common_tags, {
    Name = "extrahop-public-${count.index + 1}"
    Type = "Public"
  })
}

# Private Subnets for ExtraHop sensors
resource "aws_subnet" "private" {
  count = length(local.availability_zones)
  
  vpc_id            = local.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.availability_zones[count.index]
  
  tags = merge(var.common_tags, {
    Name = "extrahop-private-${count.index + 1}"
    Type = "Private"
  })
}

# Route table for public subnets
resource "aws_route_table" "public" {
  count = var.vpc_id == "" ? 1 : 0
  
  vpc_id = local.vpc_id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
  
  tags = merge(var.common_tags, {
    Name = "extrahop-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = var.vpc_id == "" ? length(aws_subnet.public) : 0
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# ExtraHop Sensor Instances
resource "aws_security_group" "extrahop" {
  name        = "extrahop-sensors"
  description = "Security group for ExtraHop sensors"
  vpc_id      = local.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # HTTPS management
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # GENEVE from GWLB
  ingress {
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "extrahop-sensors-sg"
  })
}

# ExtraHop instances
resource "aws_instance" "extrahop" {
  count = length(aws_subnet.private)

  ami                    = var.extrahop_ami_id
  instance_type         = var.extrahop_instance_type
  key_name              = var.key_pair_name
  subnet_id             = aws_subnet.private[count.index].id
  vpc_security_group_ids = [aws_security_group.extrahop.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
  }

  tags = merge(var.common_tags, {
    Name = "extrahop-sensor-${count.index + 1}"
    Role = "ExtraHop-Sensor"
  })
}

# Elastic IPs for ExtraHop management
resource "aws_eip" "extrahop" {
  count = length(aws_instance.extrahop)

  instance = aws_instance.extrahop[count.index].id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "extrahop-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Gateway Load Balancer Module
module "gwlb" {
  source = "./modules/gwlb"
  
  vpc_id               = local.vpc_id
  subnet_ids           = aws_subnet.private[*].id
  extrahop_instance_ids = aws_instance.extrahop[*].id
  
  tags = var.common_tags
}

# Traffic Mirroring Module
module "traffic_mirroring" {
  source = "./modules/traffic-mirroring"
  
  vpc_id                    = local.vpc_id
  subnet_ids                = aws_subnet.public[*].id
  gwlb_service_name         = module.gwlb.vpc_endpoint_service_name
  mirror_tag_key           = var.mirror_tag_key
  mirror_tag_values        = var.mirror_tag_values
  
  tags = var.common_tags
}