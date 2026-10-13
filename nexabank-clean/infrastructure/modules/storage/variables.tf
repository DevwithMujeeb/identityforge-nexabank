variable "name" {
  description = "Base name prefix for storage resources (pass the root local.name, e.g. nexabank-prod)."
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all storage resources (pass the root var.tags)."
  type        = map(string)
  default     = {}
}

# Backup and logs bucket

variable "s3_bucket_name" {
  description = "Explicit bucket name. Leave empty to auto-generate as <name>-backup-logs-<random hex>."
  type        = string
  default     = ""
}

variable "s3_kms_key_arn" {
  description = "ARN of the KMS key used for S3 server-side encryption. Wire this from the kms module at the root."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old object versions before deleting them (versioning is on, so overwritten or deleted objects pile up otherwise)."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the buckets even when they contain objects. Keep false in production."
  type        = bool
  default     = false
}

# ECR

variable "create_ecr_repository" {
  description = "Create the ECR repository for the API gateway image"
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "ECR repository name. Empty = <name>-gateway."
  type        = string
  default     = ""
}

variable "ecr_kms_key_arn" {
  description = "KMS key for ECR image encryption. null = AWS-managed AES256."
  type        = string
  default     = null
}

variable "ecr_keep_last_images" {
  description = "Number of most recent images to keep; older ones expire"
  type        = number
  default     = 20
}

# ALB access logs

variable "create_alb_logs_bucket" {
  description = "Create a separate bucket for ALB access logs. ALB logging only supports SSE-S3 encryption, so it cannot use the KMS-encrypted backup bucket."
  type        = bool
  default     = false
}

variable "alb_logs_retention_days" {
  description = "Days to keep ALB access logs"
  type        = number
  default     = 90
}
