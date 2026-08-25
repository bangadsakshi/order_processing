aws_region = "ap-south-1"
project_name = "company-orders"
environment = "staging"

availability_zones = ["ap-south-1a", "ap-south-1b"]

app_image_tag = "bootstrap"
instance_type = "t3.small"
min_size = 2
desired_capacity = 2
max_size = 6

db_instance_class = "db.t4g.small"
db_multi_az = true

github_org = "YOUR_GITHUB_ORG"
github_repo = "YOUR_GITHUB_REPO"

enable_https = false
acm_certificate_arn = ""
root_domain = ""
