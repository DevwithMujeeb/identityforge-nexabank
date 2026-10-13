data "aws_caller_identity" "current" {}

locals {
  name       = "${var.project_name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# RDS Enhanced Monitoring
data "aws_iam_policy_document" "rds_monitoring_assume" {
  count = var.create_rds_monitoring_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    # Confused-deputy protection: only RDS acting for this account
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  count = var.create_rds_monitoring_role ? 1 : 0

  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume[0].json

  tags = merge(local.common_tags, { Name = "${local.name}-rds-monitoring" })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.create_rds_monitoring_role ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ECS (gateway)
data "aws_iam_policy_document" "ecs_assume" {
  count = var.create_ecs_roles ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# Execution role which is used by ECS itself to pull the image and write logs
resource "aws_iam_role" "ecs_execution" {
  count = var.create_ecs_roles ? 1 : 0

  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume[0].json

  tags = merge(local.common_tags, { Name = "${local.name}-ecs-execution" })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count = var.create_ecs_roles ? 1 : 0

  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Optional: read specific secrets to inject into the container as env vars
data "aws_iam_policy_document" "ecs_execution_secrets" {
  count = var.create_ecs_roles && length(var.execution_secret_arns) > 0 ? 1 : 0

  statement {
    sid       = "ReadInjectedSecrets"
    actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameters"]
    resources = var.execution_secret_arns
  }

  dynamic "statement" {
    for_each = length(var.execution_kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptSecrets"
      actions   = ["kms:Decrypt"]
      resources = var.execution_kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  count = var.create_ecs_roles && length(var.execution_secret_arns) > 0 ? 1 : 0

  name   = "${local.name}-ecs-execution-secrets"
  role   = aws_iam_role.ecs_execution[0].id
  policy = data.aws_iam_policy_document.ecs_execution_secrets[0].json
}

# Task role: what the gateway container itself may call. Empty by default.
resource "aws_iam_role" "ecs_task" {
  count = var.create_ecs_roles ? 1 : 0

  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume[0].json

  tags = merge(local.common_tags, { Name = "${local.name}-ecs-task" })
}

data "aws_iam_policy_document" "ecs_exec" {
  count = var.create_ecs_roles && var.enable_ecs_exec ? 1 : 0

  statement {
    sid = "EcsExecChannels"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_exec" {
  count = var.create_ecs_roles && var.enable_ecs_exec ? 1 : 0

  name   = "${local.name}-ecs-exec"
  role   = aws_iam_role.ecs_task[0].id
  policy = data.aws_iam_policy_document.ecs_exec[0].json
}

resource "aws_iam_role_policy" "ecs_task_custom" {
  count = var.create_ecs_roles && var.task_policy_json != null ? 1 : 0

  name   = "${local.name}-ecs-task-custom"
  role   = aws_iam_role.ecs_task[0].id
  policy = var.task_policy_json
}

# Secret read access for instance roles
data "aws_iam_policy_document" "secret_read" {
  for_each = var.secret_read_grants

  statement {
    sid       = "ReadOwnSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = each.value.secret_arns
  }

  dynamic "statement" {
    for_each = length(each.value.kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptOwnSecrets"
      actions   = ["kms:Decrypt"]
      resources = each.value.kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "secret_read" {
  for_each = var.secret_read_grants

  name   = "${local.name}-${each.key}-secret-read"
  role   = each.value.role_name
  policy = data.aws_iam_policy_document.secret_read[each.key].json
}
