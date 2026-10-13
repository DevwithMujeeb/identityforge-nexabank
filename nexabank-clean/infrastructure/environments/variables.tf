# GENERAL

variable "aws_region" {
  description = "AWS region where NexaBank infrastructure will be deployed"
  type        = string
}

variable "project_name" {
  description = "Project name used as a prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}

# NETWORKING

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "enable_s3_gateway_endpoint" {
  description = "Create an S3 gateway VPC endpoint"
  type        = bool
  default     = true
}

# SECURITY

variable "admin_cidr_blocks" {
  description = "CIDRs allowed to SSH to the bastion"
  type        = list(string)

  validation {
    condition = (
      length(var.admin_cidr_blocks) > 0 &&
      alltrue([
        for c in var.admin_cidr_blocks : can(cidrhost(c, 0))
      ])
    )
    error_message = "admin_cidr_blocks must contain at least one valid CIDR."
  }

  validation {
    condition     = !contains(var.admin_cidr_blocks, "0.0.0.0/0")
    error_message = "admin_cidr_blocks must not contain 0.0.0.0/0."
  }
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the public ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_http_listener" {
  description = "Allow HTTP port 80 (redirects to HTTPS when a certificate is set)"
  type        = bool
  default     = true
}

variable "gateway_port" {
  description = "API gateway listening port (Kong 8000, APISIX 9080)"
  type        = number
  default     = 8000
}

variable "keycloak_port" {
  description = "Keycloak listening port"
  type        = number
  default     = 8443
}

variable "ca_port" {
  description = "Certificate Authority listening port (Smallstep 9000, EJBCA 8443)"
  type        = number
  default     = 9000
}

variable "db_port" {
  description = "PostgreSQL database port"
  type        = number
  default     = 5432
}

variable "ssh_port" {
  description = "SSH port"
  type        = number
  default     = 22
}

# ALB

variable "health_check_path" {
  description = "Path the ALB probes on the gateway (must return a healthy status)"
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes that count as healthy"
  type        = string
  default     = "200-399"
}

variable "certificate_arn" {
  description = "ACM certificate ARN in af-south-1 (null = HTTP-only, dev only)"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion (true for prod)"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "ALB idle connection timeout in seconds"
  type        = number
  default     = 60
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs (null = disabled)"
  type        = string
  default     = null
}

#  KMS

variable "deletion_window_in_days" {
  description = "Waiting period before scheduled KMS key deletion"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

# ALB OUTPUTS

output "alb_dns_name" {
  description = "ALB DNS name (we point the domain here)"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route 53 alias records)"
  value       = module.alb.alb_zone_id
}

output "alb_target_group_arn" {
  description = "Gateway target group  (the ECS service is attached to this)"
  value       = module.alb.target_group_arn
}


# RDS

variable "rds_engine_version" {
  description = "PostgreSQL version (major-only lets AWS pick the latest minor)"
  type        = string
  default     = "17"
}

variable "rds_instance_class" {
  description = "RDS primary instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_replica_instance_class" {
  description = "RDS replica instance class (null = same as primary)"
  type        = string
  default     = null
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage in GiB"
  type        = number
  default     = 100

  validation {
    condition     = var.rds_allocated_storage >= 20
    error_message = "rds_allocated_storage must be at least 20 GiB."
  }
}

variable "rds_max_allocated_storage" {
  description = "RDS storage autoscaling ceiling in GiB"
  type        = number
  default     = 500

  validation {
    condition     = var.rds_max_allocated_storage == 0 || var.rds_max_allocated_storage >= var.rds_allocated_storage
    error_message = "rds_max_allocated_storage must be 0 or greater than/equal to rds_allocated_storage."
  }
}

variable "rds_multi_az" {
  description = "Synchronous standby for automatic failover"
  type        = bool
  default     = false
}

variable "rds_create_read_replica" {
  description = "Create the AZ-2 read replica"
  type        = bool
  default     = true
}

variable "rds_db_name" {
  description = "Initial database created on the primary"
  type        = string
  default     = "nexabank"
}

variable "rds_master_username" {
  description = "RDS master username (not the reserved word admin)"
  type        = string
  default     = "nexabank_admin"
}

variable "rds_backup_retention_period" {
  description = "Primary automated backup retention in days (1-35)"
  type        = number
  default     = 14

  validation {
    condition     = var.rds_backup_retention_period >= 1 && var.rds_backup_retention_period <= 35
    error_message = "rds_backup_retention_period must be between 1 and 35 days."
  }
}

variable "rds_replica_backup_retention_period" {
  description = "Replica automated backup retention in days (0 disables)"
  type        = number
  default     = 7

  validation {
    condition     = var.rds_replica_backup_retention_period >= 0 && var.rds_replica_backup_retention_period <= 35
    error_message = "rds_replica_backup_retention_period must be between 0 and 35 days."
  }
}

variable "rds_backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "02:00-03:00"
}

variable "rds_maintenance_window" {
  description = "Weekly maintenance window (UTC); must not overlap the backup window"
  type        = string
  default     = "sun:03:30-sun:04:30"
}

variable "rds_apply_immediately" {
  description = "Apply changes immediately instead of in the next maintenance window"
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "Block RDS deletion"
  type        = bool
  default     = true
}

variable "rds_enable_performance_insights" {
  description = "Enable Performance Insights (7-day retention)"
  type        = bool
  default     = true
}

variable "rds_monitoring_role_arn" {
  description = "IAM role ARN for Enhanced Monitoring (null = disabled until the IAM module exists)"
  type        = string
  default     = null
}

variable "rds_monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (used only when a role ARN is set)"
  type        = number
  default     = 60

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.rds_monitoring_interval)
    error_message = "rds_monitoring_interval must be 1, 5, 10, 15, 30 or 60."
  }
}

# COMPUTE

variable "bastion_instance_type" {
  description = "Bastion instance type (x86_64)"
  type        = string
  default     = "t3.small"
}

variable "keycloak_instance_type" {
  description = "Keycloak instance type (x86_64, JVM app: size to your load)"
  type        = string
  default     = "t3.large"
}

variable "ca_instance_type" {
  description = "CA instance type (x86_64)"
  type        = string
  default     = "t3.small"
}

variable "gateway_image_tag" {
  description = "Tag of the gateway image in the ECR repo (use an immutable version such as 1.0.0, never latest)"
  type        = string
}
