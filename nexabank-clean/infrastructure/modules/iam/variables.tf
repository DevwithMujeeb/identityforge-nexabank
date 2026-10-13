variable "project_name" {
  description = "Project name used as a prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}

# RDS Enhanced Monitoring

variable "create_rds_monitoring_role" {
  description = "Create the role RDS assumes to publish Enhanced Monitoring metrics"
  type        = bool
  default     = true
}

# ECS

variable "create_ecs_roles" {
  description = "Create the ECS task execution role and task role for the API gateway"
  type        = bool
  default     = true
}

variable "execution_secret_arns" {
  description = "Secrets Manager or SSM parameter ARNs the execution role may read to inject secrets into containers"
  type        = list(string)
  default     = []
}

variable "execution_kms_key_arns" {
  description = "KMS key ARNs the execution role may decrypt (for secrets encrypted with a customer-managed key)"
  type        = list(string)
  default     = []
}

variable "enable_ecs_exec" {
  description = "Let tasks use ECS Exec (SSM-based shell into containers). Off by default."
  type        = bool
  default     = false
}

variable "task_policy_json" {
  description = "Optional inline IAM policy (JSON) for the task role: what the gateway container itself may call. null = no permissions."
  type        = string
  default     = null
}

# Instance role secret access

variable "secret_read_grants" {
  description = <<-EOT
    Read-only access to specific secrets for instance roles created by the compute module.
    Key = a label, role_name = the compute module's iam_role_name output.
    Grant each server only its own secret, never the RDS master secret.
  EOT
  type = map(object({
    role_name    = string
    secret_arns  = list(string)
    kms_key_arns = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for g in var.secret_read_grants : length(g.secret_arns) > 0])
    error_message = "Each secret_read_grants entry needs at least one secret ARN."
  }
}
