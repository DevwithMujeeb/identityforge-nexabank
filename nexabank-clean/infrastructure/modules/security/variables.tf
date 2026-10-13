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

variable "admin_cidr_blocks" {
  description = "Admin source CIDRs allowed to SSH to the bastion (e.g. [\"203.0.113.10/32\"]). Must not be 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidr_blocks) > 0 && alltrue([for c in var.admin_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "admin_cidr_blocks must contain at least one valid IPv4 CIDR."
  }

  validation {
    condition     = !contains(var.admin_cidr_blocks, "0.0.0.0/0")
    error_message = "admin_cidr_blocks must not open the bastion to the whole internet (0.0.0.0/0)."
  }
}

variable "alb_ingress_cidrs" {
  description = "Source CIDRs allowed to reach the ALB (user traffic)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_http_listener" {
  description = "Allow port 80 on the ALB (for an HTTP to HTTPS redirect listener)"
  type        = bool
  default     = true
}

variable "gateway_port" {
  description = "Port the API gateway container listens on (Kong proxy 8000, Apache APISIX 9080)"
  type        = number
  default     = 8000
}

variable "keycloak_port" {
  description = "Port Keycloak listens on (8443 HTTPS, 8080 HTTP)"
  type        = number
  default     = 8443
}

variable "ca_port" {
  description = "Port the CA listens on (Smallstep CA 9000, EJBCA 8443)"
  type        = number
  default     = 9000
}

variable "db_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "ssh_port" {
  description = "SSH port used by the bastion and for bastion-to-host SSH"
  type        = number
  default     = 22
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
