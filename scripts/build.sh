#!/usr/bin/env bash
# Builds the app and the Lambda container image. Run from the repo root or anywhere.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_NAME="${IMAGE_NAME:-turboorders}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "==> Building the Quarkus app (mvn package)"
./mvnw -q package -DskipTests

echo "==> Building the Lambda container image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker build -f src/main/docker/Dockerfile.lambda -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "==> Done. Image: ${IMAGE_NAME}:${IMAGE_TAG}"
