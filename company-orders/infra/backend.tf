terraform {
  backend "s3" {
    bucket         = "company-orders-tfstate"
    key            = "dev/state/terraform.tfstate"
    region         = "ap-south-1"
  }
}
