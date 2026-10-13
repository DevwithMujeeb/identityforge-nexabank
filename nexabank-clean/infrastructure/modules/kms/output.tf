output "key_arns" {
  description = "Map of purpose => KMS key ARN"
  value       = { for k, v in aws_kms_key.nexabank : k => v.arn }
}

output "key_ids" {
  description = "Map of purpose => KMS key ID"
  value       = { for k, v in aws_kms_key.nexabank : k => v.key_id }
}

output "rds_key_arn" {
  description = "KMS key ARN for RDS (primary and read replica)"
  value       = aws_kms_key.nexabank["rds"].arn
}

output "s3_key_arn" {
  description = "KMS key ARN for the S3 backup/log bucket"
  value       = aws_kms_key.nexabank["s3"].arn
}

output "ebs_key_arn" {
  description = "KMS key ARN for EBS volumes (EC2 and ASG launch templates)"
  value       = aws_kms_key.nexabank["ebs"].arn
}
