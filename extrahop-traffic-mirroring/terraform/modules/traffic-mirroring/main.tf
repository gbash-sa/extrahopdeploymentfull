# Traffic Mirror Filter
resource "aws_ec2_traffic_mirror_filter" "main" {
  description = "Traffic mirror filter for ${var.environment}"
  tags        = var.tags
}

# Default accept rules
resource "aws_ec2_traffic_mirror_filter_rule" "ingress_accept" {
  description              = "Accept all ingress traffic"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.main.id
  rule_number              = 200
  traffic_direction        = "ingress"
  rule_action              = "accept"
  destination_cidr_block   = "0.0.0.0/0"
  source_cidr_block        = "0.0.0.0/0"
}

resource "aws_ec2_traffic_mirror_filter_rule" "egress_accept" {
  description              = "Accept all egress traffic"
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.main.id
  rule_number              = 201
  traffic_direction        = "egress"
  rule_action              = "accept"
  destination_cidr_block   = "0.0.0.0/0"
  source_cidr_block        = "0.0.0.0/0"
}

# VPC Endpoint for GWLB
resource "aws_vpc_endpoint" "gwlb" {
  service_name      = var.gwlb_service_name
  subnet_ids        = var.endpoint_subnet_ids
  vpc_endpoint_type = "GatewayLoadBalancer"
  vpc_id            = var.vpc_id
  tags              = var.tags
}

# Traffic Mirror Target
resource "aws_ec2_traffic_mirror_target" "main" {
  description                       = "Traffic mirror target for ${var.environment}"
  gateway_load_balancer_endpoint_id = aws_vpc_endpoint.gwlb.id
  tags                              = var.tags
}

# Create Lambda package
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda"
  output_path = "/tmp/ndr-monitoring-lambda.zip"
}

# Lambda function for automated traffic mirroring
resource "aws_lambda_function" "mirroring" {
  filename                       = data.archive_file.lambda.output_path
  function_name                  = "${var.environment}-ndr-monitoring-mirroring"
  role                          = var.lambda_role_arn
  handler                       = "ndr_monitoring_mirroring.handler"
  source_code_hash              = data.archive_file.lambda.output_base64sha256
  runtime                       = "python3.11"
  timeout                       = 900
  memory_size                   = 512
  reserved_concurrent_executions = 1

  environment {
    variables = merge({
      traffic_mirror_target_id   = aws_ec2_traffic_mirror_target.main.id
      traffic_mirror_filter_id   = aws_ec2_traffic_mirror_filter.main.id
      vpc_id                     = var.vpc_id
      region                     = var.region
    }, var.environment_tags)
  }

  tags = var.tags
}

# CloudWatch Events for instance lifecycle
resource "aws_cloudwatch_event_rule" "instance_lifecycle" {
  name          = "${var.environment}-ndr-monitoring-lifecycle"
  state         = "ENABLED"
  description   = "Trigger on EC2 instance state changes"
  
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    detail-type   = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["pending", "running", "stopping", "stopped", "shutting-down", "terminated"]
    }
  })

  tags = var.tags
}

# Scheduled rule for gap detection
resource "aws_cloudwatch_event_rule" "scheduled_sync" {
  name                = "${var.environment}-ndr-monitoring-scheduled"
  description         = "Runs every hour to detect gaps"
  schedule_expression = "rate(1 hour)"
  tags                = var.tags
}

# Event targets
resource "aws_cloudwatch_event_target" "mirroring_lifecycle" {
  rule = aws_cloudwatch_event_rule.instance_lifecycle.name
  arn  = aws_lambda_function.mirroring.arn
}

resource "aws_cloudwatch_event_target" "mirroring_scheduled" {
  rule = aws_cloudwatch_event_rule.scheduled_sync.name
  arn  = aws_lambda_function.mirroring.arn
}

# Lambda permissions
resource "aws_lambda_permission" "cloudwatch_lifecycle" {
  statement_id  = "AllowExecutionFromCloudWatchLifecycle"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mirroring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_lifecycle.arn
}

resource "aws_lambda_permission" "cloudwatch_scheduled" {
  statement_id  = "AllowExecutionFromCloudWatchScheduled"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mirroring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled_sync.arn
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "mirroring" {
  name              = "/aws/lambda/${aws_lambda_function.mirroring.function_name}"
  retention_in_days = 7
  tags              = var.tags
}