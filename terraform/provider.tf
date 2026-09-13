# Author: Hadi Yahya
# Date: 2026-09-13
# Project: DevOps Bootcamp Project

# DevOps AWS Region

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.8.0"
}

provider "aws" {
  region = "ap-southeast-1"
}