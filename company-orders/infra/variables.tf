variable "project_name" {
  description = "Project name used for AWS resource naming"
  type        = string
  default     = "company-orders"
}
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
variable "aws_region" {
  description = "AWS region for the dev environment"
  type        = string
  default     = "ap-south-1"
}
variable "enable_https" {
  type    = bool
  default = false
}
variable "acm_certificate_arn" {
  type    = string
  default = ""
}
variable "app_image_tag" {
  type    = string
  default = "bootstrap"
}
variable "min_size" {
  type    = number
  default = 2
}
variable "desired_capacity" {
  type    = number
  default = 2
}
variable "max_size" {
  type    = number
  default = 6
}
variable "root_domain" {
  type    = string
  default = ""
}
variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}
variable "availability_zones" {
  description = "Availability Zones used by the dev environment"
  type        = list(string)

  default = [
    "ap-south-1a",
    "ap-south-1b"
  ]
}
variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)

  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
}
variable "private_app_subnet_cidrs" {
  description = "Private application subnet CIDRs"
  type        = list(string)

  default = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
}
variable "private_db_subnet_cidrs" {
  description = "Private database subnet CIDRs"
  type        = list(string)

  default = [
    "10.0.21.0/24",
    "10.0.22.0/24"
  ]
}
variable "single_nat_gateway" {
  description = "Use a single NAT Gateway to reduce dev cost"
  type        = bool
  default     = true
}
variable "container_port" {
  description = "Port exposed by the application container"
  type        = number
  default     = 8000
}
variable "health_check_path" {
  description = "Application health check endpoint"
  type        = string
  default     = "/health"
}
variable "app_log_level" {
  description = "Application logging level"
  type        = string
  default     = "INFO"
}
variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID. Leave empty for automatic lookup."
  type        = string
  default     = ""
}
variable "instance_type" {
  description = "EC2 instance type for development"
  type        = string
  default     = "t3.micro"
}
variable "asg_min_size" {
  description = "Minimum application instances"
  type        = number
  default     = 2
}
variable "asg_desired_capacity" {
  description = "Desired application instances"
  type        = number
  default     = 2
}
variable "asg_max_size" {
  description = "Maximum application instances"
  type        = number
  default     = 4
}
variable "root_volume_size" {
  description = "EC2 root EBS volume size in GB"
  type        = number
  default     = 20
}
variable "db_engine" {
  description = "RDS database engine"
  type        = string
  default     = "postgres"
}
variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}
variable "db_instance_class" {
  description = "RDS instance class for development"
  type        = string
  default     = "db.t4g.micro"
}
variable "db_name" {
  description = "Application database name"
  type        = string
  default     = "orders"
}
variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "ordersadmin"
}
variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}
variable "db_allocated_storage" {
  description = "Initial RDS storage in GB"
  type        = number
  default     = 20
}
variable "db_max_allocated_storage" {
  description = "Maximum RDS storage in GB"
  type        = number
  default     = 50
}
variable "db_backup_retention_period" {
  description = "RDS automated backup retention in days"
  type        = number
  default     = 1
}
variable "db_multi_az" {
  description = "Enable RDS Multi-AZ. Disabled for low-cost dev."
  type        = bool
  default     = false
}
variable "db_deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
  default     = false
}
variable "db_skip_final_snapshot" {
  description = "Skip final RDS snapshot when destroying dev"
  type        = bool
  default     = true
}
variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "company-order-dev-repo"
}
variable "ecr_image_tag_mutability" {
  description = "ECR image tag behavior"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition = contains(
      ["MUTABLE", "IMMUTABLE"],
      var.ecr_image_tag_mutability
    )

    error_message = "ECR image tag mutability must be MUTABLE or IMMUTABLE."
  }
}
variable "orders_bucket_name" {
  description = "S3 bucket used for CSV order uploads. Empty means generate a unique name."
  type        = string
  default     = ""
}
variable "statistics_bucket_name" {
  description = "S3 bucket used for order statistics. Empty means generate a unique name."
  type        = string
  default     = ""
}
variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}
variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 60
}
variable "lambda_memory_size" {
  description = "Lambda memory allocation in MB"
  type        = number
  default     = 256
}
variable "cloudfront_price_class" {
  description = "CloudFront price class for development"
  type        = string
  default     = "PriceClass_100"
}
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}
variable "app_5xx_alarm_threshold" {
  description = "ALB 5xx threshold for the application alarm"
  type        = number
  default     = 5
}
variable "ec2_cpu_alarm_threshold" {
  description = "EC2 CPU utilization alarm threshold"
  type        = number
  default     = 70
}
variable "github_org" {
  description = "GitHub username or organization"
  type        = string
  default     = "bangadsakshi"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "orders_processing"
}

variable "github_branch" {
  description = "GitHub branch permitted to deploy"
  type        = string
  default     = "main"
}
variable "common_tags" {
  description = "Common tags applied to AWS resources"
  type        = map(string)

  default = {
    Project     = "company-orders"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Owner       = "DevOps"
  }
}
