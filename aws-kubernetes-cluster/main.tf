terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.67.0"
    }
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_ami" "selected" {
  owners = ["self", "amazon"]

  filter {
    name   = "image-id"
    values = ["ami-0199ac7c9fbf9ed83"]
  }
}