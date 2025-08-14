# terraform/outputs.tf
output "vpc_id" {
  description = "VPC ID being used"
  value       = local.vpc_id
}

output "extrahop_management_ips" {
  description = "ExtraHop management IP addresses"
  value       = aws_eip.extrahop[*].public_ip
}

output "extrahop_instance_ids" {
  description = "ExtraHop instance IDs"
  value       = aws_instance.extrahop[*].id
}

output "gwlb_arn" {
  description = "Gateway Load Balancer ARN"
  value       = module.gwlb.gwlb_arn
}

output "vpc_endpoint_service_name" {
  description = "VPC Endpoint Service name for GWLB"
  value       = module.gwlb.vpc_endpoint_service_name
}

output "traffic_mirror_target_id" {
  description = "Traffic Mirror Target ID"
  value       = module.traffic_mirroring.mirror_target_id
}

output "lambda_function_name" {
  description = "Lambda function name for traffic mirroring automation"
  value       = module.traffic_mirroring.lambda_function_name
}