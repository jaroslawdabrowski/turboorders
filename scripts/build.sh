#!/usr/bin/env bash
# Builds the app and the Lambda container image. Run from the repo root or anywhere.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_NAME="${IMAGE_NAME:-turboorders}"

# Default to a unique tag per build (git commit + a dirty marker for uncommitted changes,
# falling back to a timestamp outside a git repo). This matters: Lambda resolves an
# image_uri's tag to a digest once at deploy time and does not notice a tag being
# overwritten later, so reusing a fixed tag like "latest" across builds means
# `terraform apply` sees the same image_uri string and skips updating the function -
# scripts/deploy.sh picks up the same tag via .image-tag below.
IMAGE_TAG="${IMAGE_TAG:-}"
if [ -z "$IMAGE_TAG" ]; then
  if git -C "$REPO_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    IMAGE_TAG="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
    git -C "$REPO_ROOT" diff --quiet --ignore-submodules HEAD -- || IMAGE_TAG="${IMAGE_TAG}-dirty"
  else
    IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
  fi
fi

echo "==> Building the Quarkus app (mvn package -Plambda)"
./mvnw -q package -Plambda -DskipTests

echo "==> Building the Lambda container image: ${IMAGE_NAME}:${IMAGE_TAG}"
docker build -f src/main/docker/Dockerfile.lambda -t "${IMAGE_NAME}:${IMAGE_TAG}" -t "${IMAGE_NAME}:latest" .

echo "$IMAGE_TAG" > target/.image-tag

echo "==> Done. Image: ${IMAGE_NAME}:${IMAGE_TAG}"
