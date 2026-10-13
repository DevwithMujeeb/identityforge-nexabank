output "bucket_id" {
  description = "Name/ID of the backup-and-logs S3 bucket."
  value       = aws_s3_bucket.backup_logs.id
}

output "bucket_arn" {
  description = "ARN of the backup-and-logs S3 bucket (use for IAM policies / bucket policies)."
  value       = aws_s3_bucket.backup_logs.arn
}

output "bucket_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.backup_logs.bucket_regional_domain_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the gateway image (null if not created). Append :<tag> for the image URI."
  value       = one(aws_ecr_repository.gateway[*].repository_url)
}

output "ecr_repository_arn" {
  description = "ECR repository ARN (null if not created)."
  value       = one(aws_ecr_repository.gateway[*].arn)
}

output "alb_logs_bucket_id" {
  description = "ALB access logs bucket name (null if not created). Waits for the delivery policy so the ALB can enable logging."
  value       = one(aws_s3_bucket.alb_logs[*].id)

  depends_on = [aws_s3_bucket_policy.alb_logs]
}
