#!/usr/bin/env bash
set -euo pipefail
API="${1:?Usage: ./scripts/generate_stats.sh http://...}"
python3 stats/generate_stats.py "$API" /tmp/index.html
BUCKET="$(terraform -chdir=infra output -raw stats_bucket_name)"
aws s3 cp /tmp/index.html "s3://$BUCKET/index.html" --content-type text/html
echo "CloudFront URL:"
terraform -chdir=infra output -raw cloudfront_domain_name
