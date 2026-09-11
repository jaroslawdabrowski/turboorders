output "function_url" {
  description = "Public HTTPS URL of the deployed app"
  value       = aws_lambda_function_url.app.function_url
}

output "ecr_repository_url" {
  description = "Push images here before the first `terraform apply` that creates the Lambda function"
  value       = aws_ecr_repository.app.repository_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.app.name
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}
