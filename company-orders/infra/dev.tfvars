aws_region = "ap-south-1"
project_name = "company-orders"
environment = "dev"

availability_zones = ["ap-south-1a", "ap-south-1b"]

app_image_tag = "bootstrap"
instance_type = "t3.micro"
min_size = 2
desired_capacity = 2
max_size = 4

db_instance_class = "db.t4g.micro"
db_multi_az = false

github_org = "bangadsakshi"
github_repo = "order_processing"

enable_https = false
acm_certificate_arn = ""
root_domain = ""
