# Gateway Load Balancer
resource "aws_lb" "gwlb" {
  name                             = "${var.environment}-extrahop-gwlb"
  load_balancer_type               = "gateway"
  enable_cross_zone_load_balancing = true
  subnets                          = var.subnet_ids
  enable_deletion_protection       = false

  tags = var.tags
}

# Target Group
resource "aws_lb_target_group" "gwlb" {
  name        = "${var.environment}-extrahop-tg"
  port        = 6081
  protocol    = "GENEVE"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    port     = 2003
    protocol = "TCP"
  }

  tags = var.tags
}

# Listener
resource "aws_lb_listener" "gwlb" {
  load_balancer_arn = aws_lb.gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gwlb.arn
  }
}

# VPC Endpoint Service
resource "aws_vpc_endpoint_service" "gwlb" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]
  
  tags = var.tags
}

# Cross-account permissions
resource "aws_vpc_endpoint_service_allowed_principal" "cross_account" {
  for_each                = var.allowed_account_ids
  vpc_endpoint_service_id = aws_vpc_endpoint_service.gwlb.id
  principal_arn          = "arn:aws:iam::${each.value}:root"
}