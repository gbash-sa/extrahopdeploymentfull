output "ndr_monitoring_role_arn" {
  description = "ARN of the NDR monitoring role"
  value       = aws_iam_role.ndr_monitoring.arn
}

output "ndr_monitoring_role_name" {
  description = "Name of the NDR monitoring role"
  value       = aws_iam_role.ndr_monitoring.name
}