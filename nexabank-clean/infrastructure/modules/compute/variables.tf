# Identity

variable "name" {
  description = "Base name for resources (e.g. nexabank-prod-keycloak)."
  type        = string

  validation {
    condition     = length(var.name) <= 50
    error_message = "name must be 50 characters or fewer (IAM role names are limited to 64)."
  }
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

# Placement

variable "subnet_ids" {
  description = "Subnets the ASG may launch into, one per AZ. Two subnets in two AZs lets the ASG relaunch in the surviving AZ."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet ID."
  }
}

variable "security_group_ids" {
  description = "Security group IDs to attach. Root wires in module.security outputs."
  type        = list(string)
}

variable "associate_public_ip_address" {
  description = "null = follow the subnet setting. true/false forces it (use true for a bastion in a public subnet that does not auto-assign)."
  type        = bool
  default     = null
}

# Permissions

variable "enable_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore (Session Manager shell access)."
  type        = bool
  default     = true
}

variable "enable_cloudwatch_agent" {
  description = "Attach CloudWatchAgentServerPolicy so the agent can ship logs and metrics."
  type        = bool
  default     = false
}

variable "extra_policy_arns" {
  description = "Additional managed policy ARNs to attach. For custom policies, attach to the iam_role_name output from the root."
  type        = list(string)
  default     = []
}

variable "enable_s3_access" {
  description = "Allow access to this instance's own prefix in the backup bucket. Off by default."
  type        = bool
  default     = false
}

variable "backup_bucket_arn" {
  description = "ARN of the S3 backup/logs bucket (required when enable_s3_access = true)."
  type        = string
  default     = ""
}

variable "s3_kms_key_arn" {
  description = "KMS key ARN protecting the bucket (required when enable_s3_access = true)."
  type        = string
  default     = ""
}

variable "s3_key_prefix" {
  description = "Bucket prefix this instance may use. null = the instance name, so instances cannot read each other's data."
  type        = string
  default     = null
}

variable "s3_allow_write" {
  description = "Allow writing objects (false = read-only access)."
  type        = bool
  default     = true
}

variable "s3_allow_delete" {
  description = "Allow deleting objects. Keep false so a compromised instance cannot erase its backups."
  type        = bool
  default     = false
}

# Compute

variable "instance_type" {
  description = "EC2 instance type (x86_64 only, the AMI lookup is x86_64)."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID. Leave empty to use the latest Amazon Linux 2023 AMI."
  type        = string
  default     = ""
}

variable "key_name" {
  description = "Existing EC2 key pair name. Leave empty for keyless SSM access."
  type        = string
  default     = ""
}

variable "ebs_kms_key_arn" {
  description = "KMS key ARN for the root EBS volume. Empty uses the AWS-managed aws/ebs key."
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 20
}

variable "user_data" {
  description = "Boot script (plain text; the module base64-encodes it)."
  type        = string
  default     = null
}

variable "metadata_hop_limit" {
  description = "IMDS hop limit. 1 for processes on the host; 2 only if containers on the instance need instance credentials."
  type        = number
  default     = 1
}

# Auto Scaling

variable "asg_min_size" {
  description = "ASG minimum size."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "ASG maximum size."
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "ASG desired capacity."
  type        = number
  default     = 1
}

variable "termination_protection" {
  description = "Protect instances from ASG scale-in (true for prod)."
  type        = bool
  default     = false
}

variable "target_group_arns" {
  description = "Load balancer target groups to register instances with (e.g. an internal NLB for Keycloak)."
  type        = list(string)
  default     = []
}

variable "health_check_type" {
  description = "EC2 or ELB. Use ELB when target_group_arns is set so unhealthy targets are replaced."
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be EC2 or ELB."
  }
}
