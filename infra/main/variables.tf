variable "region" {
  description = "AWS region for all TurboOrders infrastructure"
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Short project name, used to prefix resource names"
  type        = string
  default     = "turboorders"
}

variable "environment" {
  description = "Deployment environment name (single environment for now: test)"
  type        = string
  default     = "test"
}

variable "image_tag" {
  description = "Tag of the Lambda container image in ECR to deploy (see scripts/deploy.sh)"
  type        = string
  default     = "latest"
}

variable "security_username" {
  description = "Basic Auth username, becomes the TURBOORDERS_SECURITY_USERNAME Lambda env var"
  type        = string
  sensitive   = true
}

variable "security_password_hash" {
  description = "BCrypt hash of the Basic Auth password, becomes the TURBOORDERS_SECURITY_PASSWORD_HASH Lambda env var"
  type        = string
  sensitive   = true
}

variable "lambda_memory_mb" {
  description = "Lambda memory allocation in MB (also determines proportional CPU)"
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda invocation timeout in seconds"
  type        = number
  default     = 15
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda function's log group"
  type        = number
  default     = 14
}
