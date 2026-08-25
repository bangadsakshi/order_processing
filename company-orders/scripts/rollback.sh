#!/usr/bin/env bash
set -euo pipefail
TAG="${1:?Usage: ./scripts/rollback.sh <previous-image-tag>}"
TFVARS="${2:-infra/dev.tfvars}"

terraform -chdir=infra apply -auto-approve \
  -var-file="$TFVARS" \
  -var="app_image_tag=$TAG"

echo "Rollback requested to image tag: $TAG"
