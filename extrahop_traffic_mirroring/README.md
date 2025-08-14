# ExtraHop Traffic Mirroring - Tag-Based Solution

This solution provides automated traffic mirroring for ExtraHop sensors using AWS Gateway Load Balancer (GWLB) and tag-based instance discovery.

## Quick Start

1. **Prerequisites**
   - Existing VPC with subnets
   - ExtraHop AMI from AWS Marketplace
   - EC2 Key Pair
   - AWS CLI and Terraform installed

2. **Configure Variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values