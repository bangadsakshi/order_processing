output "api_base_url" {
  value = var.enable_https ? "https://${var.root_domain}" : "http://${aws_lb.app.dns_name}"
}

output "alb_dns_name" { value = aws_lb.app.dns_name }
output "target_group_arn" { value = aws_lb_target_group.app.arn }
output "asg_name" { value = aws_autoscaling_group.app.name }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "bulk_bucket_name" { value = aws_s3_bucket.bulk.bucket }
output "stats_bucket_name" { value = aws_s3_bucket.stats.bucket }
output "cloudfront_domain_name" { value = aws_cloudfront_distribution.stats.domain_name }
output "lambda_name" { value = aws_lambda_function.bulk.function_name }
output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }
output "db_endpoint" { value = aws_db_instance.db.address }

output "app_log_group" { value = aws_cloudwatch_log_group.app.name }
