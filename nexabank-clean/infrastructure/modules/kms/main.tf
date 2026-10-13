data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name       = "${var.project_name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # via_service lets principals in specified account use the key. Only EBS needs it for the Auto Scaling service-linked role to use the key to launch instances with encrypted volumes.
  keys = {
    rds = { description = "RDS PostgreSQL storage encryption", via_service = "" }
    s3  = { description = "S3 backup and log bucket encryption", via_service = "" }
    ebs = { description = "EBS volume encryption for EC2 and ASG instances", via_service = "ec2" }
  }
}

data "aws_iam_policy_document" "key" {
  for_each = local.keys

  # Delegates access control to IAM. for IAM policies to grant key access.

  statement {
    sid       = "EnableIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = each.value.via_service != "" ? [each.value.via_service] : []

    content {
      sid = "AllowUseThroughService"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [local.account_id]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["${statement.value}.${local.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_kms_key" "nexabank" {
  for_each = local.keys

  description             = "${local.name} - ${each.value.description}"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key[each.key].json

  tags = merge(local.common_tags, { Name = "${local.name}-${each.key}-key" })
}

resource "aws_kms_alias" "nexabank" {
  for_each = local.keys

  name          = "alias/${local.name}-${each.key}"
  target_key_id = aws_kms_key.nexabank[each.key].key_id
}
