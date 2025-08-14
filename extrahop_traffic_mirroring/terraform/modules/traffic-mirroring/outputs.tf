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

output "mirroring_lambda_function_name" {
  description = "Name of the mirroring Lambda function"
  value       = aws_lambda_function.mirroring.function_name
}

output "cloud_properties_lambda_function_name" {
  description = "Name of the cloud properties Lambda function"
  value       = aws_lambda_function.cloud_properties.function_name
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for cloud properties"
  value       = aws_sqs_queue.cloud_properties.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for cloud properties"
  value       = aws_sqs_queue.cloud_properties.arn
}