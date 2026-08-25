variable "aws_region" { 
  type = string
  default = "ap-south-1"
   }
variable "project_name" { type = string }
variable "environment" { type = string }

variable "vpc_cidr" { 
  type = string 
  default = "10.0.0.0/16" 
  }

variable "availability_zones" {
  type = list(string)
}

variable "app_image_tag" {
  type    = string
  default = "bootstrap"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" { 
  type = number 
  default = 2 
}
variable "desired_capacity" { 
  type = number 
  default = 2 
}
variable "max_size" { 
  type = number 
  default = 6 
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "orders"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "github_org" { type = string }
variable "github_repo" { type = string }

variable "enable_https" {
  type    = bool
  default = false
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "root_domain" {
  type    = string
  default = ""
}
