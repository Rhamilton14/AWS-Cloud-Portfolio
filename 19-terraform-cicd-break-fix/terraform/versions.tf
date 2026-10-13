terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # State lives in S3 (created by ../bootstrap). Bucket and region come from
  # backend.hcl so no account-specific names are committed:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "project-19/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # S3-native state locking, no DynamoDB table needed
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Repo      = "aws-cloud-portfolio"
    }
  }
}
