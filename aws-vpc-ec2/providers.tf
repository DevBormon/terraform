terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.67.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-2"
}