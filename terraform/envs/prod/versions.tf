terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "devops-bootcamp-terraform-hadiyahya"
    key            = "prod/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "devops-bootcamp-terraform-lock-hadiyahya"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
