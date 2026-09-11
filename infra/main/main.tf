locals {
  name = "${var.project}-${var.environment}"
}

# --- ECR: holds the Quarkus Lambda container image ---
# Create this first (`terraform apply -target=aws_ecr_repository.app`), push an
# image with scripts/build.sh + scripts/deploy.sh, then apply everything else -
# aws_lambda_function.app below fails to create if the image doesn't exist yet.
resource "aws_ecr_repository" "app" {
  name                 = local.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# --- DynamoDB: single on-demand table, no capacity planning needed ---
resource "aws_dynamodb_table" "app" {
  name         = local.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }
}

# --- SSM Parameter Store: Basic Auth credentials, managed from the AWS console ---
# SecureString on the free default AWS-managed key (alias/aws/ssm) - not a customer-
# managed KMS key, which would cost ~$1/mo for zero benefit here. `ignore_changes`
# means Terraform seeds the value once (from var.security_username/password_hash,
# themselves defaulted so routine applies never need to supply anything) and never
# again overwrites whatever's actually in SSM - rotate the credential by editing the
# parameter's value in the AWS console/CLI, then run `terraform apply` (no -var flags
# needed) to push it into the Lambda's environment.
resource "aws_ssm_parameter" "security_username" {
  name  = "/${local.name}/security/username"
  type  = "SecureString"
  value = var.security_username

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "security_password_hash" {
  name = "/${local.name}/security/password-hash"
  type = "SecureString"
  # coalesce so a first-ever apply still works if security_password_hash isn't
  # supplied - the placeholder is an obviously-invalid BCrypt hash (fails every
  # login) rather than a real value baked into version control.
  value = coalesce(var.security_password_hash, "$2a$10$0000000000000000000000CHANGE.ME.IN.SSM")

  lifecycle {
    ignore_changes = [value]
  }
}

# --- IAM: least-privilege Lambda execution role ---
resource "aws_iam_role" "lambda_exec" {
  name = "${local.name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name = "${local.name}-dynamodb-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      Resource = [
        aws_dynamodb_table.app.arn,
        "${aws_dynamodb_table.app.arn}/index/*",
      ]
    }]
  })
}

# --- Lambda: Quarkus app as a container image, exposed via a Function URL ---
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "app" {
  function_name = local.name
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
  timeout       = var.lambda_timeout_seconds
  memory_size   = var.lambda_memory_mb

  environment {
    variables = {
      TURBOORDERS_SECURITY_USERNAME      = aws_ssm_parameter.security_username.value
      TURBOORDERS_SECURITY_PASSWORD_HASH = aws_ssm_parameter.security_password_hash.value
      QUARKUS_DYNAMODB_AWS_REGION        = var.region
    }
  }

  depends_on = [aws_cloudwatch_log_group.app, aws_iam_role_policy_attachment.lambda_basic_execution]
}

resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE" # AWS-layer auth is off; Basic Auth is enforced inside the app
}

resource "aws_lambda_permission" "public_url" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# AWS requires BOTH InvokeFunctionUrl and InvokeFunction on the resource policy for a
# NONE-auth Function URL to work (since Oct 2025) - see the aws_lambda_permission
# comment below for why this can't be scoped to "via function URL only" yet.
resource "aws_lambda_permission" "public_invoke" {
  statement_id  = "AllowPublicInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "*"
  # AWS's recommended policy also scopes this to Condition lambda:InvokedViaFunctionUrl=true,
  # but aws_lambda_permission doesn't expose that condition key yet
  # (https://github.com/hashicorp/terraform-provider-aws/issues/44829), so this grants
  # public lambda:InvokeFunction broadly, not just via the Function URL. Basic Auth inside
  # the app (platform/security/) is the actual access control either way - this is a known,
  # accepted gap until the provider adds support.
}
