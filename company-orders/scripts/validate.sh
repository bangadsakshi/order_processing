#!/usr/bin/env bash
set -euo pipefail
python3 -m compileall app lambda stats
python3 -m pytest -q app/test_main.py
terraform -chdir=infra fmt -check
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
echo "Local validation passed."
