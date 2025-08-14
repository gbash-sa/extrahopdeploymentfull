output "gwlb_arn" {
  description = "ARN of the Gateway Load Balancer"
  value       = aws_lb.gwlb.arn
}

output "endpoint_service_name" {
  description = "Name of the VPC endpoint service"
  value       = aws_vpc_endpoint_service.gwlb.service_name
}

output "endpoint_service_id" {
  description = "ID of the VPC endpoint service"
  value       = aws_vpc_endpoint_service.gwlb.id
}