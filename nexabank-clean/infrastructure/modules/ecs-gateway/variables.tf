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

# Wiring

variable "subnet_ids" {
  description = "Private subnets for the tasks (networking private_subnet_id_primary, plus the secondary for multi-AZ)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet ID."
  }
}

variable "security_group_ids" {
  description = "Security groups for the tasks (security module gateway_sg_id)"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ALB target group to register tasks with (alb module target_group_arn)"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role (iam module ecs_execution_role_arn)"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role (iam module ecs_task_role_arn)"
  type        = string
}

# Container

variable "container_image" {
  description = "Full image URI with an immutable tag, e.g. <account>.dkr.ecr.af-south-1.amazonaws.com/nexabank-gateway:1.0.0. Avoid latest."
  type        = string
}

variable "container_name" {
  description = "Container name (must match what the ALB registers)"
  type        = string
  default     = "gateway"
}

variable "container_port" {
  description = "Port the NexaBank API listens on; must match gateway_port, the security group, and the ALB target group"
  type        = number
  default     = 3000

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "cpu" {
  description = "Task CPU units (256, 512, 1024, 2048, 4096). Must be a valid Fargate pair with memory."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Task memory in MiB. 1024 is valid with 512 CPU units."
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. Must match how the image was built."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "environment_variables" {
  description = "Plain environment variables for the container (e.g. the Keycloak URL)"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets injected as environment variables: name => Secrets Manager or SSM parameter ARN. The execution role needs read access (iam module execution_secret_arns)."
  type        = map(string)
  default     = {}
}

variable "readonly_root_filesystem" {
  description = "Mount the container root filesystem read-only. Kong and APISIX write to local paths, so test before enabling."
  type        = bool
  default     = false
}

variable "container_health_check_command" {
  description = "Optional container-level health check, e.g. [\"CMD-SHELL\", \"kong health\"]. null = rely on the ALB health check."
  type        = list(string)
  default     = null
}

# Service

variable "desired_count" {
  description = "Initial number of tasks. After creation, capacity is managed by autoscaling min/max."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}

variable "health_check_grace_period_seconds" {
  description = "Time the ALB ignores failing health checks after a task starts"
  type        = number
  default     = 60
}

variable "enable_execute_command" {
  description = "ECS Exec (shell into containers). Also needs enable_ecs_exec in the iam module. Off by default."
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "CloudWatch Container Insights on the cluster (extra CloudWatch cost)"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the gateway log group"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs supports (for example 30, 90, 365)."
  }
}

# Autoscaling

variable "enable_autoscaling" {
  description = "Scale the service on average CPU"
  type        = bool
  default     = true
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 2
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 6
}

variable "autoscaling_cpu_target" {
  description = "Target average CPU utilization (percent)"
  type        = number
  default     = 60
}
