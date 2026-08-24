import csv
import hashlib
import io
import json
import os
import urllib.error
import urllib.request

import boto3

s3 = boto3.client("s3")
sm = boto3.client("secretsmanager")

API_BASE_URL = os.environ["API_BASE_URL"].rstrip("/")
IMPORT_TOKEN_SECRET_ARN = os.environ["IMPORT_TOKEN_SECRET_ARN"]

def token():
    secret = json.loads(sm.get_secret_value(SecretId=IMPORT_TOKEN_SECRET_ARN)["SecretString"])
    return secret["token"]

def post_order(row, key):
    body = json.dumps({
        "customer_id": row["customer_id"].strip(),
        "product_id": row["product_id"].strip(),
        "quantity": int(row["quantity"]),
    }).encode()
    req = urllib.request.Request(
        f"{API_BASE_URL}/internal/import-order",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token()}",
            "X-Idempotency-Key": key,
        },
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.loads(response.read().decode())

def lambda_handler(event, context):
    results = {"processed": 0, "failed": 0, "errors": []}

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        obj = s3.get_object(Bucket=bucket, Key=key)
        content = obj["Body"].read().decode("utf-8-sig")

        reader = csv.DictReader(io.StringIO(content))
        required = {"customer_id", "product_id", "quantity"}
        if not reader.fieldnames or not required.issubset(set(reader.fieldnames)):
            raise ValueError(f"CSV must contain columns: {sorted(required)}")

        for row_number, row in enumerate(reader, start=2):
            try:
                if not row.get("customer_id", "").strip():
                    raise ValueError("customer_id is required")
                if not row.get("product_id", "").strip():
                    raise ValueError("product_id is required")
                quantity = int(row.get("quantity", ""))
                if quantity <= 0:
                    raise ValueError("quantity must be greater than zero")
                row["quantity"] = str(quantity)

                idempotency_key = hashlib.sha256(
                    f"{bucket}:{key}:{row_number}".encode()
                ).hexdigest()

                post_order(row, idempotency_key)
                results["processed"] += 1

            except Exception as exc:
                results["failed"] += 1
                results["errors"].append({
                    "row": row_number,
                    "error": str(exc),
                })

    print(json.dumps(results))
    return results
