terraform {
  backend "s3" {
    bucket = "8byte-terraform-state-prod"
    key    = "infra/terraform.tfstate"
    region = "ap-south-1"
    dynamodb_table = "8byte-terraform-lock"
    encrypt = true
  }
}