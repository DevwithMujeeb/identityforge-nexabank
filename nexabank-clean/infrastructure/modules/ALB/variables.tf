variable "project_name" {
  description = "Project name used as a prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID from the networking module"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB (networking alb_subnet_ids); must span 2 AZs"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least two Availability Zones."
  }
}

variable "security_group_id" {
  description = "ALB security group ID from the security module (alb_sg_id)"
  type        = string
}

variable "gateway_port" {
  description = "Port the API gateway container listens on; must match the security module's gateway_port"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "Path the ALB probes on the gateway. Configure a route that returns 200 here."
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "HTTP status codes that count as healthy"
  type        = string
  default     = "200-399"
}

variable "certificate_arn" {
  description = "ACM certificate ARN (must be issued in af-south-1). Null = HTTP-only, for dev."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_http_listener" {
  description = "Create the port 80 listener. With a certificate it redirects to HTTPS; without one it forwards (dev only). Keep in sync with the security module."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion (set true for prod)"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Idle connection timeout in seconds"
  type        = number
  default     = 60
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs (null = disabled). Bucket must use SSE-S3 and allow ELB log delivery."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
