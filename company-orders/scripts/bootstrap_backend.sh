#!/usr/bin/env bash
set -euo pipefail
REGION="${1:-ap-south-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="company-orders-tfstate"

aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null || aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  $( [ "$REGION" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=$REGION" )

aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "TF_STATE_BUCKET=$BUCKET"
echo "Use this bucket in the Terraform backend initialization."
