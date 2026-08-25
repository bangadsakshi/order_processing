# X-Company Order Processing Service

## Selected model

This implementation uses **EC2 instances directly running Docker containers**, behind an internet-facing Application Load Balancer and an Auto Scaling Group.

It was selected because the goal is to demonstrate a migration from serverless compute to server-based/containerized compute while retaining managed AWS services where useful.

## Requirements covered

- VPC across two AZs
- Two public and four private subnets: two application + two database
- Internet Gateway
- NAT Gateway per AZ
- ALB
- EC2 + Docker + Auto Scaling Group
- RDS PostgreSQL private and encrypted
- Security Groups with ALB -> app -> DB trust
- Stateless application
- POST/GET order APIs
- Health endpoint
- S3 CSV upload
- S3 -> Lambda bulk processing
- Per-row validation and error handling
- Idempotent CSV row processing
- S3 private statistics page
- CloudFront with Origin Access Control
- ECR
- Terraform
- GitHub Actions
- OIDC
- Trivy scan
- Rolling/zero-downtime deployment
- Automatic rollback on ASG refresh failure
- CloudWatch logs
- CloudWatch alarms
- Horizontal scaling
- Operational rollback script
- Failure testing instructions

## 1. Prerequisites

Install:

- AWS CLI v2
- Terraform >= 1.6
- Docker
- Python 3.12
- Git

Configure:

```bash
aws configure
aws sts get-caller-identity
terraform version
docker version
```

## 2. Bootstrap Terraform state

```bash
chmod +x scripts/*.sh
./scripts/bootstrap_backend.sh ap-south-1
```

For GitHub Actions, create repository secrets:

```text
AWS_DEPLOY_ROLE_ARN
TF_STATE_BUCKET
```

The role ARN is printed by:

```bash
terraform -chdir=infra output -raw github_actions_role_arn
```

## 3. First deployment

The first deployment has a bootstrap dependency: EC2 needs an image in ECR before it can start the application.

Run:

```bash
./scripts/bootstrap.sh infra/dev.tfvars bootstrap
```

This creates ECR first, builds the image, pushes it, and then creates the rest of the stack.

Get API URL:

```bash
terraform -chdir=infra output -raw api_base_url
```

Health:

```bash
API_URL=$(terraform -chdir=infra output -raw api_base_url)
curl "$API_URL/health"
```

## 4. API

Create:

```bash
curl -X POST "$API_URL/orders" \
  -H "Content-Type: application/json" \
  -H "X-Idempotency-Key: demo-001" \
  -d '{"customer_id":"CUST-001","product_id":"PROD-100","quantity":2}'
```

Get an order:

```bash
curl "$API_URL/orders/ORDER_ID"
```

Recent orders:

```bash
curl "$API_URL/orders?limit=20"
```

Health:

```bash
curl "$API_URL/health"
```

Change an order status just to check:

```bash
./scripts/set_status.sh ORDER_ID COMPLETED
```

Statistics:

```bash
curl "$API_URL/stats"
```

## 5. Network/request flow

Customer:

```text
Internet
 -> ALB public subnets :80/443
 -> ALB Security Group
 -> App Security Group :8080
 -> EC2 private subnet
 -> RDS Security Group :5432
 -> RDS private subnets
```

Private EC2 outbound:

```text
EC2 private subnet
 -> private route table
 -> NAT Gateway in same AZ
 -> Internet Gateway
 -> Internet
```

Database:

```text
DB subnet
 -> local VPC route only
```

## 6. Bulk import

CSV format:

```csv
customer_id,product_id,quantity
CUST-001,PROD-100,2
CUST-002,PROD-200,1
CUST-003,PROD-100,5
```

Upload:

```bash
./scripts/upload_csv.sh sample-orders.csv
```

Flow:

```text
S3 ObjectCreated
 -> Lambda
 -> validate each row
 -> POST /internal/import-order
 -> ALB
 -> EC2 application
 -> RDS
```

The Lambda is not granted DB access. The DB security group therefore continues to trust only the application layer.

Invalid rows are isolated:

```text
row 2 success
row 3 invalid -> recorded in Lambda result/log
row 4 success
```

Duplicate processing is prevented using:

```text
SHA256(bucket + key + row_number)
```

stored as a unique DB idempotency key.

For very large imports, evolve this to:

```text
S3 -> Lambda -> SQS -> worker -> RDS
                         |
                         -> DLQ
```

## 7. Statistics

Generate:

```bash
API_URL=$(terraform -chdir=infra output -raw api_base_url)
./scripts/generate_stats.sh "$API_URL"
```

The static HTML is stored in a private S3 bucket.

CloudFront uses Origin Access Control:

```text
Browser -> CloudFront -> private S3
```

The S3 bucket is never made public.

## 8. Database

RDS PostgreSQL:

- private subnets
- encryption enabled
- automated backups
- no public access
- DB SG accepts TCP 5432 only from App SG
- credentials generated/managed by Secrets Manager
- EC2 IAM role reads the RDS secret

The application uses SQLAlchemy pooling:

```text
pool_size = 5
max_overflow = 5
```

## 9. Security

No credentials are committed.

No application instance is publicly addressable.

Security path:

```text
Internet -> ALB
ALB -> App
App -> DB
```

## 10. CI/CD

Push to main:

```text
GitHub
 -> pytest
 -> Docker build
 -> Trivy HIGH/CRITICAL scan
 -> ECR push with Git SHA
 -> Terraform apply
 -> ASG rolling instance refresh
 -> health check
```

The image is immutable and tagged with the Git commit SHA.

## 11. Zero downtime

The ASG uses:

```text
min healthy percentage = 50%
ELB health checks = /health
instance warmup = 180 seconds
auto rollback = true
```

A new version does not receive ALB traffic until it is healthy.

## 12. Rollback

List ECR images:

```bash
aws ecr describe-images \
  --repository-name "$(terraform -chdir=infra output -raw ecr_repository_url | sed 's|.*/||')" \
  --query 'imageDetails[*].imageTags'
```

Rollback:

```bash
./scripts/rollback.sh PREVIOUS_GIT_SHA
```

Because the image is immutable and Git-SHA tagged, the previous version can be restored without rebuilding.

## 13. Failure demonstration

Find instances:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$(terraform -chdir=infra output -raw asg_name)" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
  --output table
```

Terminate one:

```bash
aws ec2 terminate-instances --instance-ids i-XXXXXXXX
```

The ASG launches a replacement. The ALB continues using the healthy instance.

Verify:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform -chdir=infra output -raw target_group_arn)"
```

## 14. 5xx troubleshooting

First inspect ALB target health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform -chdir=infra output -raw target_group_arn)"
```

Then application logs:

```bash
aws logs tail "/company-orders/dev/application" --since 30m --follow
```

Then RDS:

```bash
aws rds describe-db-instances \
  --db-instance-identifier company-orders-dev-postgres
```

Check:

```text
ALB 5xx
 -> target health
 -> EC2/Docker logs
 -> RDS connections/latency
 -> security groups/routes
 -> NAT/external dependencies
```

## 15. Scaling

ASG:

```text
min 2
desired 2
max 4 dev
max 6 staging/prod
CPU target 60%
```

At 5-10x traffic:

```text
ALB traffic rises
 -> EC2 CPU rises
 -> ASG adds instances
 -> new instances pass /health
 -> ALB sends traffic to them
```

Potential bottlenecks other than CPU:

1. RDS connections.
2. RDS IOPS/query latency.
3. NAT Gateway throughput/cost.
4. ALB request rate.
5. Lambda concurrency during bulk imports.

## 16. Monitoring

CloudWatch alarms:

- unhealthy ALB targets
- ALB target 5xx
- EC2 ASG CPU

Logs:

```text
/company-orders/dev/application
/aws/lambda/company-orders-dev-bulk-import
```

## 17. Environment separation

Use separate tfvars:

```bash
terraform -chdir=infra apply -var-file=dev.tfvars
terraform -chdir=infra apply -var-file=staging.tfvars
terraform -chdir=infra apply -var-file=prod.tfvars
```

For real production use separate AWS accounts and separate Terraform state.

## 18. Destroy

```bash
terraform -chdir=infra destroy -var-file=dev.tfvars
```

Do not use destructive destroy workflows against production.

## 19. Production hardening

Before calling this production-grade, add:

- ACM + HTTPS/443
- Route 53 DNS
- AWS WAF
- RDS Proxy
- Alembic migrations
- SQS + DLQ for large imports
- SNS notification for alarms
- CloudWatch dashboard
- structured JSON logs
- OpenTelemetry/X-Ray
- least-privilege GitHub IAM
- load tests
- separate production AWS account
- RDS deletion protection
- final snapshot/backup retention
