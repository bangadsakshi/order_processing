#!/usr/bin/env bash
set -euo pipefail

TFVARS="${1:-infra/dev.tfvars}"
TAG="${2:-bootstrap}"
REGION="$(awk -F'"' '/^aws_region/ {print $2; exit}' "$TFVARS")"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="company-orders-tfstate-${ACCOUNT_ID}-${REGION}"

cd infra
terraform init -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="key=company-orders/${TAG}/terraform.tfstate" \
  -backend-config="region=${REGION}"

terraform fmt -check
terraform validate

terraform apply -auto-approve -var-file="$TFVARS" -target=aws_ecr_repository.app

REPO="$(terraform output -raw ecr_repository_url)"
cd ..
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REPO"
docker build -t "$REPO:$TAG" app
docker push "$REPO:$TAG"

cd infra
terraform apply -auto-approve -var-file="$TFVARS" -var="app_image_tag=$TAG"

echo "API: $(terraform output -raw api_base_url)"
echo "CloudFront: $(terraform output -raw cloudfront_domain_name)"
echo "GitHub deploy role: $(terraform output -raw github_actions_role_arn)"
