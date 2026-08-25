data "aws_caller_identity" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-${var.environment}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = ["10.0.1.0/24", "10.0.2.0/24"][count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-${var.environment}-public-${count.index + 1}" }
}

resource "aws_subnet" "app" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = ["10.0.11.0/24", "10.0.12.0/24"][count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-${var.environment}-app-${count.index + 1}" }
}

resource "aws_subnet" "db" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = ["10.0.21.0/24", "10.0.22.0/24"][count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-${var.environment}-db-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-public-rt" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  tags   = { Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}" }
}

resource "aws_route_table" "app" {
  count  = 2
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-app-rt-${count.index + 1}" }
}

resource "aws_route" "app_default" {
  count                  = 2
  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

resource "aws_route_table" "db" {
  count  = 2
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-db-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db[count.index].id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-alb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "App SG"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "DB SG"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count             = var.enable_https ? 1 : 0
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_db" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_security_group_rule" "db_egress" {
  type              = "egress"
  security_group_id = aws_security_group.db.id
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2" {
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ],
        Resource = aws_ecr_repository.app.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ],
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      },
      {
        Effect = "Allow",
        Action = ["secretsmanager:GetSecretValue"],
        Resource = [
          aws_db_instance.db.master_user_secret[0].secret_arn,
          aws_secretsmanager_secret.import_token.arn
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-${var.environment}-app"
  image_scanning_configuration { scan_on_push = true }
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  tags                 = { Name = "${var.project_name}-${var.environment}-app" }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/company-orders/${var.environment}/application"
  retention_in_days = 30
}

resource "aws_secretsmanager_secret" "import_token" {
  name = "${var.project_name}/${var.environment}/import-token"
}

resource "random_password" "import_token" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret_version" "import_token" {
  secret_id     = aws_secretsmanager_secret.import_token.id
  secret_string = jsonencode({ token = random_password.import_token.result })
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-${var.environment}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_db_instance" "db" {
  identifier                  = "${var.project_name}-${var.environment}-postgres"
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = var.db_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  db_name                     = var.db_name
  username                    = "ordersadmin"
  manage_master_user_password = true
  port                        = 5432
  db_subnet_group_name        = aws_db_subnet_group.db.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  multi_az                    = var.db_multi_az
  backup_retention_period     = 7
  deletion_protection         = false
  skip_final_snapshot         = true
  storage_encrypted           = true
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  copy_tags_to_snapshot       = true
  tags                        = { Name = "${var.project_name}-${var.environment}-postgres" }
}

resource "aws_lb" "app" {
  name                       = "${var.project_name}-${var.environment}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"
    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    dynamic "forward" {
      for_each = var.enable_https ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.app.arn
        }
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix            = "${var.project_name}-${var.environment}-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    region                  = var.aws_region
    repository_url          = aws_ecr_repository.app.repository_url
    image_tag               = var.app_image_tag
    log_group               = aws_cloudwatch_log_group.app.name
    db_secret_arn           = aws_db_instance.db.master_user_secret[0].secret_arn
    import_token_secret_arn = aws_secretsmanager_secret.import_token.arn
    environment             = var.environment
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}-app"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-${var.environment}-asg"
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  vpc_zone_identifier       = aws_subnet.app[*].id
  health_check_type         = "ELB"
  health_check_grace_period = 180
  target_group_arns         = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage       = 50
      instance_warmup              = 180
      auto_rollback                = true
      scale_in_protected_instances = "Refresh"
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-app"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-${var.environment}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name  = "${var.project_name}-${var.environment}-unhealthy-targets"
  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name  = "${var.project_name}-${var.environment}-alb-5xx"
  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name  = "${var.project_name}-${var.environment}-ec2-cpu"
  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_s3_bucket" "bulk" {
  bucket        = "${var.project_name}-${var.environment}-bulk-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "bulk" {
  bucket                  = aws_s3_bucket.bulk.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "bulk" {
  bucket = aws_s3_bucket.bulk.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bulk" {
  bucket = aws_s3_bucket.bulk.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket" "stats" {
  bucket        = "${var.project_name}-${var.environment}-stats-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "stats" {
  bucket                  = aws_s3_bucket.stats.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "stats" {
  bucket = aws_s3_bucket.stats.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "stats" {
  bucket = aws_s3_bucket.stats.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_cloudfront_origin_access_control" "stats" {
  name                              = "${var.project_name}-${var.environment}-stats-oac"
  description                       = "CloudFront access to private stats S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "stats" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.stats.bucket_regional_domain_name
    origin_id                = "stats-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.stats.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "stats-s3"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "stats_bucket_policy" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.stats.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.stats.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "stats" {
  bucket = aws_s3_bucket.stats.id
  policy = data.aws_iam_policy_document.stats_bucket_policy.json
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-${var.environment}-bulk-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.bulk.arn}/*"
      },
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = aws_secretsmanager_secret.import_token.arn
      }
    ]
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "bulk" {
  function_name    = "${var.project_name}-${var.environment}-bulk-import"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 300
  memory_size      = 512

  environment {
    variables = {
      API_BASE_URL            = "http://${aws_lb.app.dns_name}"
      IMPORT_TOKEN_SECRET_ARN = aws_secretsmanager_secret.import_token.arn
    }
  }
}

resource "aws_s3_bucket_notification" "bulk" {
  bucket = aws_s3_bucket.bulk.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.bulk.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.s3]
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bulk.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.bulk.arn
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.bulk.function_name}"
  retention_in_days = 30
}

