output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.deployment_validator.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.deployment_validator.arn
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda_role.arn
}
