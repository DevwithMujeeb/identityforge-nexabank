variable "project_name" {
  description = "Project name used as a prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Wiring from other modules

variable "db_subnet_group_name" {
  description = "DB subnet group from the networking module (spans AZ-1 and AZ-2)"
  type        = string
}

variable "security_group_id" {
  description = "RDS security group ID from the security module (rds_sg_id)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for storage encryption (kms module rds_key_arn)"
  type        = string
}

variable "az_primary" {
  description = "AZ for the primary instance (networking az_primary)"
  type        = string
}

variable "az_secondary" {
  description = "AZ for the read replica (networking az_secondary)"
  type        = string
}

# Engine and sizing

variable "engine_version" {
  description = "PostgreSQL version. A major-only value (17) lets AWS pick the latest minor."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "Primary instance class. Check availability in af-south-1 before choosing."
  type        = string
  default     = "db.t3.micro"
}

variable "replica_instance_class" {
  description = "Replica instance class (null = same as primary)"
  type        = string
  default     = null
}

variable "allocated_storage" {
  description = "Initial storage in GiB"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB (0 disables autoscaling)"
  type        = number
  default     = 500
}

variable "multi_az" {
  description = "Create a synchronous standby for automatic failover (roughly doubles primary cost)"
  type        = bool
  default     = false
}

variable "create_read_replica" {
  description = "Create the AZ-2 read replica"
  type        = bool
  default     = true
}

variable "db_port" {
  description = "PostgreSQL port; must match the security module's db_port"
  type        = number
  default     = 5432
}

# Database and credentials

variable "db_name" {
  description = "Initial database created on the primary"
  type        = string
  default     = "nexabank"
}

variable "master_username" {
  description = "Master username (do not use the reserved word admin)"
  type        = string
  default     = "nexabank_admin"
}

# Backups and maintenance

variable "backup_retention_period" {
  description = "Days to keep automated backups on the primary (must be 1 or more for a read replica)"
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 (required for read replicas)."
  }
}

variable "replica_backup_retention_period" {
  description = "Days to keep automated backups on the replica (0 disables)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "02:00-03:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC); must not overlap the backup window"
  type        = string
  default     = "sun:03:30-sun:04:30"
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of in the next maintenance window"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block deletion of the instances (set true for prod)"
  type        = bool
  default     = true
}

# Monitoring

variable "enable_performance_insights" {
  description = "Enable Performance Insights (7-day retention is free)"
  type        = bool
  default     = true
}

variable "monitoring_role_arn" {
  description = "IAM role ARN for Enhanced Monitoring (null = disabled). Created in the iam module later."
  type        = string
  default     = null
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (used only when monitoring_role_arn is set)"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
