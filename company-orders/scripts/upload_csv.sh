#!/usr/bin/env bash
set -euo pipefail
FILE="${1:?Usage: ./scripts/upload_csv.sh file.csv}"
BUCKET="$(terraform -chdir=infra output -raw bulk_bucket_name)"
aws s3 cp "$FILE" "s3://$BUCKET/incoming/$(basename "$FILE")"
echo "Uploaded. Lambda will process it automatically."
