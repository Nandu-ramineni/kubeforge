#!/usr/bin/env bash
set -euo pipefail

# Builds the three Phase 3 Dockerfiles and pushes them to the ECR repos
# Phase 5's Terraform created. Reads the actual repo URLs from Terraform
# state rather than having them typed in twice (once in Terraform, once
# here) - the two would inevitably drift.
#
# Usage: scripts/build-and-push-ecr.sh [tag]
#   tag defaults to a timestamp. NEVER defaults to 'latest' - see
#   docs/architecture.md Section 10: immutable ECR repos (Phase 5) actively
#   reject a second push to the same tag, so 'latest' wouldn't even work
#   past the first push. A real git-SHA tag arrives properly in Phase 7's CI;
#   this is the manual equivalent until then.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infrastructure/terraform/environments/dev"
TAG="${1:-manual-$(date +%Y%m%d%H%M%S)}"

command -v aws >/dev/null || { echo "AWS CLI is not installed"; exit 1; }
command -v docker >/dev/null || { echo "Docker is not installed / not running"; exit 1; }

# Tiny JSON-field extractor using node, not python3 - python3/python often
# resolve to a Windows Store install stub that does nothing useful even when
# no real Python is installed, and node is already a hard requirement for
# this whole project, so it's the safer default to reach for here.
json_field() {
  JSON_INPUT="$1" JSON_KEY="$2" node -e "console.log(JSON.parse(process.env.JSON_INPUT)[process.env.JSON_KEY])"
}

echo "==> Reading ECR repo URLs from Terraform state"
cd "$TF_DIR"
ECR_JSON=$(terraform output -json ecr_repository_urls)
API_REPO=$(json_field "$ECR_JSON" "kubeforge-api")
WORKER_REPO=$(json_field "$ECR_JSON" "kubeforge-worker")
FRONTEND_REPO=$(json_field "$ECR_JSON" "kubeforge-frontend")
REGISTRY="${API_REPO%%/*}" # everything before the first '/' is the registry host
# Registry host looks like <account-id>.dkr.ecr.<region>.amazonaws.com -
# extracting the region from it avoids a second, separate way of specifying
# the region that could drift from what Terraform actually used.
AWS_REGION=$(echo "$REGISTRY" | cut -d. -f4)

echo "==> Logging in to ECR ($REGISTRY)"
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Building images (tag: $TAG)"
docker build -t "$API_REPO:$TAG"      "$ROOT_DIR/services/api"
docker build -t "$WORKER_REPO:$TAG"   "$ROOT_DIR/services/worker"
docker build -t "$FRONTEND_REPO:$TAG" "$ROOT_DIR/services/frontend"

echo "==> Pushing images"
docker push "$API_REPO:$TAG"
docker push "$WORKER_REPO:$TAG"
docker push "$FRONTEND_REPO:$TAG"

echo
echo "Done. Image tag: $TAG"
echo "  $API_REPO:$TAG"
echo "  $WORKER_REPO:$TAG"
echo "  $FRONTEND_REPO:$TAG"
echo
echo "Next: scripts/deploy-to-eks.sh $TAG"
