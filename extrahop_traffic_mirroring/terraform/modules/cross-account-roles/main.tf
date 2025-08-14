# IAM role for Lambda functions
resource "aws_iam_role" "ndr_monitoring" {
  name = "${var.environment}-ndr-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for traffic mirroring operations
resource "aws_iam_policy" "ndr_monitoring" {
  name        = "${var.environment}-ndr-monitoring"
  description = "Policy for NDR monitoring operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTrafficMirrorSession",
          "ec2:DeleteTrafficMirrorSession",
          "ec2:ModifyTrafficMirrorSession",
          "ec2:DescribeTrafficMirrorSessions",
          "ec2:DescribeTrafficMirrorTargets",
          "ec2:DescribeTrafficMirrorFilters",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVpcs",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:*ndr-monitoring-api-secret*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = "arn:aws:sqs:*:*:*ndr-monitoring-cloud-properties*"
      }
    ]
  })

  tags = var.tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ndr_monitoring" {
  role       = aws_iam_role.ndr_monitoring.name
  policy_arn = aws_iam_policy.ndr_monitoring.arn
}