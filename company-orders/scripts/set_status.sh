#!/usr/bin/env bash
set -euo pipefail
ORDER_ID="${1:?Usage: ./scripts/set_status.sh ORDER_ID STATUS}"
STATUS="${2:?Usage: ./scripts/set_status.sh ORDER_ID STATUS}"
API="$(terraform -chdir=infra output -raw api_base_url)"
echo "This helper requires the import token from Secrets Manager."
SECRET_ARN="$(terraform -chdir=infra state show aws_secretsmanager_secret.import_token 2>/dev/null | awk -F' = ' '/^arn/ {gsub(/"/,"",$2); print $2; exit}')"
TOKEN="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
curl -fsS -X PATCH "$API/internal/orders/$ORDER_ID/status" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"status\":\"$STATUS\"}"
echo
