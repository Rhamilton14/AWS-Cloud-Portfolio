# One-time setup, run by hand with your own admin credentials:
#   cd bootstrap && terraform init && terraform apply -var github_repo=OWNER/REPO
# Creates the remote state bucket and the two roles GitHub Actions assumes
# through OIDC, so no long-lived AWS keys are ever stored in GitHub.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the roles, as owner/name"
  type        = string
  default     = "rhamilton14/aws-cloud-portfolio"
}

data "aws_caller_identity" "current" {}

# ---------- Remote state ----------

resource "aws_s3_bucket" "state" {
  # Account ID in the name keeps it globally unique without hardcoding anything.
  bucket = "tf-webapp-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # every state change is recoverable
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- GitHub OIDC ----------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  state_access = {
    Effect   = "Allow"
    Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
}

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Pull requests, plus main for the nightly drift check.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:pull_request",
        "repo:${var.github_repo}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs running in the "production" GitHub environment, which
    # requires a manual approval, can make changes.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:production"]
    }
  }
}

# Plan role: read everything, write only the state lock.
resource "aws_iam_role" "plan" {
  name               = "github-tf-webapp-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [local.state_access] })
}

# Apply role: only the services this stack uses. No IAM permissions,
# because the app stack creates no IAM resources.
resource "aws_iam_role" "apply" {
  name               = "github-tf-webapp-apply"
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
}

resource "aws_iam_role_policy" "apply" {
  name = "tf-webapp-deploy"
  role = aws_iam_role.apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.state_access,
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "cloudwatch:*",
          "sns:*",
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.region }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*"
      },
      {
        # The ELB and Auto Scaling service-linked roles, created on first use.
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = [
              "elasticloadbalancing.amazonaws.com",
              "autoscaling.amazonaws.com",
            ]
          }
        }
      },
    ]
  })
}

output "state_bucket" {
  description = "Put this in terraform/backend.hcl and the AWS_STATE_BUCKET repo variable"
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Repo variable AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Repo variable AWS_APPLY_ROLE_ARN"
  value       = aws_iam_role.apply.arn
}
