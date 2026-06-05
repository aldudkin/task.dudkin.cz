terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 6.0" # Any 6.x but not higher/lower minor
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}