output "traffic_mirror_filter_id" {
  description = "ID of the traffic mirror filter"
  value       = aws_ec2_traffic_mirror_filter.main.id
}

output "traffic_mirror_target_id" {
  description = "ID of the traffic mirror target"
  value       = aws_ec2_traffic_mirror_target.main.id
}

output "vpc_endpoint_id" {
  description = "ID of the VPC endpoint"
  value       = aws_vpc_endpoint.gwlb.id
}

output "lambda_function_name" {
  description = "Name of the mirroring Lambda function"
  value       = aws_lambda_function.mirroring.function_name
}