variable "aws_region" {
  type    = string
  default = null
}

provider "aws" {
  region = var.aws_region != null ? var.aws_region : "ap-south-2"
}
