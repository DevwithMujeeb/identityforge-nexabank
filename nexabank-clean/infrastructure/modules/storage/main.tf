resource "random_id" "bucket_suffix" {
  byte_length = 4
}

data "aws_caller_identity" "current" {}

# ELB's regional account, for regions that still need it in the log delivery policy
data "aws_elb_service_account" "main" {}

locals {
  name        = var.name
  common_tags = var.common_tags
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name}-backup-logs-${random_id.bucket_suffix.hex}"
  ecr_name    = var.ecr_repository_name != "" ? var.ecr_repository_name : "${local.name}-gateway"
}

# Backup and logs bucket (SSE-KMS)

resource "aws_s3_bucket" "backup_logs" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name    = "${local.name}-backup-logs"
    Purpose = "backup-and-logs"
  })
}

resource "aws_s3_bucket_versioning" "backup_logs" {
  bucket = aws_s3_bucket.backup_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_logs" {
  bucket = aws_s3_bucket.backup_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.s3_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "backup_logs" {
  bucket                  = aws_s3_bucket.backup_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any non-TLS request
data "aws_iam_policy_document" "backup_logs" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backup_logs.arn, "${aws_s3_bucket.backup_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backup_logs" {
  bucket = aws_s3_bucket.backup_logs.id
  policy = data.aws_iam_policy_document.backup_logs.json

  depends_on = [aws_s3_bucket_public_access_block.backup_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_logs" {
  bucket = aws_s3_bucket.backup_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  # Whole bucket: with versioning on
  rule {
    id     = "housekeeping"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.backup_logs]
}

# ECR repository for the API gateway image

resource "aws_ecr_repository" "gateway" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = local.ecr_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_destroy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.ecr_kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.ecr_kms_key_arn
  }

  tags = merge(local.common_tags, { Name = local.ecr_name })
}

resource "aws_ecr_lifecycle_policy" "gateway" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.gateway[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_keep_last_images
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ALB access logs bucket (SSE-S3: ALB cannot write to a KMS-encrypted bucket

resource "aws_s3_bucket" "alb_logs" {
  count = var.create_alb_logs_bucket ? 1 : 0

  bucket        = "${local.name}-alb-logs-${random_id.bucket_suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name    = "${local.name}-alb-logs"
    Purpose = "alb-access-logs"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count = var.create_alb_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count = var.create_alb_logs_bucket ? 1 : 0

  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count = var.create_alb_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.alb_logs_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "alb_logs" {
  count = var.create_alb_logs_bucket ? 1 : 0

  # Allow both forms: the log delivery service principal, and the regional ELB account that regions launched before August 2022 historically required.
  statement {
    sid       = "AllowAlbLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs[0].arn, "${aws_s3_bucket.alb_logs[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count = var.create_alb_logs_bucket ? 1 : 0

  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
