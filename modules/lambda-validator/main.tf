# ===========================================
# Lambda Deployment Validator
# ===========================================
# ECS Blue/Green POST_TEST_TRAFFIC_SHIFT 검증용 Lambda

data "archive_file" "validator_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/deployment-validator"
  output_path = "${path.module}/../../lambda/deployment-validator.zip"
}

resource "aws_lambda_function" "deployment_validator" {
  filename         = data.archive_file.validator_zip.output_path
  function_name    = "${var.project_name}-deployment-validator"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.validator_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      BACKEND_URL = var.backend_url
      TEST_PORT   = var.backend_test_port
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-deployment-validator"
  })
}

# ===========================================
# IAM Role for Lambda
# ===========================================

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-validator-lambda-role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ===========================================
# CloudWatch Log Group
# ===========================================

resource "aws_cloudwatch_log_group" "validator_logs" {
  name              = "/aws/lambda/${var.project_name}-deployment-validator"
  retention_in_days = 7

  tags = var.tags
}
