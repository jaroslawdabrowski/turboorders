#!/usr/bin/env bash
# Pushes the locally built Lambda image to ECR and applies the Terraform stack.
#
# First-time setup (once per AWS account):
#   1. cd infra/bootstrap && terraform init && terraform apply
#   2. cd infra/main && terraform init -backend-config="bucket=<state bucket from step 1>" \
#        -backend-config="dynamodb_table=<lock table from step 1>" -backend-config="region=eu-central-1"
#   3. terraform apply -target=aws_ecr_repository.app   (creates just the ECR repo)
#   4. Set TF_VAR_security_username / TF_VAR_security_password_hash (see application.properties
#      for how to generate a dev-style BCrypt hash), then run this script.
#
# Every subsequent deploy: scripts/build.sh && scripts/deploy.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra/main"

IMAGE_NAME="${IMAGE_NAME:-turboorders}"
AWS_REGION="${AWS_REGION:-eu-central-1}"

# Match whatever unique tag scripts/build.sh generated (see its comment for why
# reusing a fixed tag like "latest" across deploys silently skips the Lambda update).
IMAGE_TAG="${IMAGE_TAG:-}"
if [ -z "$IMAGE_TAG" ]; then
  if [ -f "$REPO_ROOT/target/.image-tag" ]; then
    IMAGE_TAG="$(cat "$REPO_ROOT/target/.image-tag")"
  else
    echo "No IMAGE_TAG set and target/.image-tag not found - run scripts/build.sh first." >&2
    exit 1
  fi
fi

cd "$INFRA_DIR"
ECR_REPOSITORY_URL="$(terraform output -raw ecr_repository_url)"

echo "==> Logging in to ECR: ${ECR_REPOSITORY_URL}"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPOSITORY_URL"

echo "==> Tagging and pushing ${IMAGE_NAME}:${IMAGE_TAG} to ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
docker push "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

echo "==> Applying Terraform (creates/updates the Lambda function to use the new image)"
terraform plan -input=false -var="image_tag=${IMAGE_TAG}" -out=.deploy.tfplan
terraform apply -input=false .deploy.tfplan
rm -f .deploy.tfplan

echo "==> Deployed. Function URL:"
terraform output -raw function_url
echo
