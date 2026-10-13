locals {
  name               = "${var.project_name}-${var.environment}"
  monitoring_enabled = var.monitoring_role_arn != null

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

#  Parameter group it is shared by the primary and the replica.

resource "aws_db_parameter_group" "nexabank" {
  name_prefix = "${local.name}-pg17-"
  family      = "postgres17"
  description = "PostgreSQL 17 parameters for ${local.name}"

  # Reject any non-TLS connection
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Log statements slower than 1 second
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name}-pg17-params" })
}

# Primary
resource "aws_db_instance" "nexabank" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  port           = var.db_port

  db_name  = var.db_name
  username = var.master_username

  # RDS creates and rotates the master password in Secrets Manager

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false

  # AZ-1 as in the diagram. availability_zone cannot be set together with multi_az.
  multi_az          = var.multi_az
  availability_zone = var.multi_az ? null : var.az_primary

  parameter_group_name = aws_db_parameter_group.nexabank.name

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-postgres-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id       = var.enable_performance_insights ? var.kms_key_arn : null
  performance_insights_retention_period = var.enable_performance_insights ? 7 : null

  monitoring_interval = local.monitoring_enabled ? var.monitoring_interval : 0
  monitoring_role_arn = var.monitoring_role_arn

  lifecycle {
    ignore_changes = [allocated_storage]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-postgres" })
}

# Read replica inherit encryption, the KMS key, credentials and the subnet group from the source.
resource "aws_db_instance" "replica" {
  count = var.create_read_replica ? 1 : 0

  identifier          = "${local.name}-postgres-replica"
  replicate_source_db = aws_db_instance.nexabank.identifier
  instance_class      = coalesce(var.replica_instance_class, var.instance_class)
  port                = var.db_port

  availability_zone      = var.az_secondary
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  multi_az               = false

  max_allocated_storage = var.max_allocated_storage
  parameter_group_name  = aws_db_parameter_group.nexabank.name

  backup_retention_period = var.replica_backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  deletion_protection = var.deletion_protection
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id       = var.enable_performance_insights ? var.kms_key_arn : null
  performance_insights_retention_period = var.enable_performance_insights ? 7 : null

  monitoring_interval = local.monitoring_enabled ? var.monitoring_interval : 0
  monitoring_role_arn = var.monitoring_role_arn

  lifecycle {
    ignore_changes = [allocated_storage]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-postgres-replica" })
}
