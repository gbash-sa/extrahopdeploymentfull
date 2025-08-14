output "vpc_id" {
  description = "VPC ID being used"
  value       = var.vpc_id
}

output "extrahop_sensor_instance_ids" {
  description = "ExtraHop sensor instance IDs"
  value       = aws_instance.extrahop[*].id
}

output "extrahop_management_ips" {
  description = "ExtraHop management interface private IPs"
  value       = aws_network_interface.extrahop_management[*].private_ip
}

output "extrahop_capture_ips" {
  description = "ExtraHop capture interface private IPs"
  value       = aws_network_interface.extrahop_capture[*].private_ip
}

output "gwlb_arn" {
  description = "Gateway Load Balancer ARN"
  value       = module.gwlb.gwlb_arn
}

output "gwlb_endpoint_service_name" {
  description = "VPC Endpoint Service name for GWLB"
  value       = module.gwlb.endpoint_service_name
}

output "traffic_mirror_target_id" {
  description = "Traffic Mirror Target ID"
  value       = module.traffic_mirroring.traffic_mirror_target_id
}

output "traffic_mirror_filter_id" {
  description = "Traffic Mirror Filter ID"
  value       = module.traffic_mirroring.traffic_mirror_filter_id
}

output "mirroring_lambda_function_name" {
  description = "Lambda function name for traffic mirroring automation"
  value       = module.traffic_mirroring.mirroring_lambda_function_name
}

output "cloud_properties_lambda_function_name" {
  description = "Lambda function name for cloud properties updates"
  value       = module.traffic_mirroring.cloud_properties_lambda_function_name
}

output "test_instance_ids" {
  description = "Test instance IDs (if created)"
  value       = var.create_test_instances ? aws_instance.test_instances[*].id : []
}

output "test_instance_private_ips" {
  description = "Test instance private IPs (if created)"
  value       = var.create_test_instances ? aws_instance.test_instances[*].private_ip : []
}

output "extrahop_api_secret_arn" {
  description = "ARN of the ExtraHop API secret"
  value       = aws_secretsmanager_secret.extrahop_api.arn
}

output "sqs_queue_url" {
  description = "SQS queue URL for cloud properties"
  value       = module.traffic_mirroring.sqs_queue_url
}

output "next_steps" {
  description = "Instructions for completing the setup"
  value = <<-EOT
    
    ExtraHop Traffic Mirroring Infrastructure Deployed!
    
    Next Steps:
    1. Update ExtraHop API credentials in Secrets Manager:
       aws secretsmanager update-secret --secret-id "${aws_secretsmanager_secret.extrahop_api.name}" --secret-string '{"api_endpoint":"your-endpoint","api_id":"your-id","api_secret":"your-secret"}'
    
    2. ExtraHop Management IPs: ${join(", ", aws_network_interface.extrahop_management[*].private_ip)}
    
    3. Test instances with mirroring enabled: ${var.create_test_instances ? join(", ", aws_instance.test_instances[*].id) : "None created"}
    
    4. To test traffic mirroring:
       - Tag any instance with "${var.mirror_tag_key}" = "${var.mirror_tag_values[0]}"
       - Check CloudWatch logs: /aws/lambda/${module.traffic_mirroring.mirroring_lambda_function_name}
    
    5. Monitor the SQS queue: ${module.traffic_mirroring.sqs_queue_url}
    
  EOT
}