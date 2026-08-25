#!/usr/bin/env bash
set -euo pipefail
ASG="$(terraform -chdir=infra output -raw asg_name)"
TG="$(terraform -chdir=infra output -raw target_group_arn)"
API="$(terraform -chdir=infra output -raw api_base_url)"

echo "=== API ==="
curl -fsS "$API/health" || true
echo

echo "=== Target health ==="
aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table

echo "=== ASG ==="
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table

echo "=== Recent application logs ==="
aws logs tail "$(terraform -chdir=infra output -raw app_log_group 2>/dev/null || echo '/company-orders/dev/application')" \
  --since 15m || true
