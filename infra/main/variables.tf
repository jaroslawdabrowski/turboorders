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

# These two are ONLY used to seed the SSM Parameter Store parameters (see
# aws_ssm_parameter.security_* in main.tf) the very first time they're created.
# After that, `lifecycle.ignore_changes` on those resources means Terraform never
# overwrites a value someone sets via the SSM console/CLI, and these variables stop
# mattering - real day-to-day credential changes happen in SSM, not here. Defaults
# exist so routine `terraform apply`/`scripts/deploy.sh` runs never need them.
variable "security_username" {
  description = "Bootstrap-only initial value for the SSM username parameter - see comment above"
  type        = string
  default     = "turboorders"
  sensitive   = true
}

variable "security_password_hash" {
  description = "Bootstrap-only initial value for the SSM password-hash parameter - see comment above"
  type        = string
  default     = null
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
