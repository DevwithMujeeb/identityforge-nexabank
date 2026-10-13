output "primary_endpoint" {
  description = "Primary hostname for write traffic"
  value       = aws_db_instance.nexabank.address
}

output "primary_port" {
  description = "Database port"
  value       = aws_db_instance.nexabank.port
}

output "primary_arn" {
  description = "Primary instance ARN"
  value       = aws_db_instance.nexabank.arn
}

output "primary_identifier" {
  description = "Primary instance identifier"
  value       = aws_db_instance.nexabank.identifier
}

output "replica_endpoint" {
  description = "Read replica hostname (null if no replica)"
  value       = one(aws_db_instance.replica[*].address)
}

output "replica_arn" {
  description = "Read replica ARN (null if no replica)"
  value       = one(aws_db_instance.replica[*].arn)
}

output "replica_identifier" {
  description = "Read replica instance identifier (null if no replica)"
  value       = one(aws_db_instance.replica[*].identifier)
}

output "db_name" {
  description = "Initial database name"
  value       = aws_db_instance.nexabank.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the managed master credentials"
  value       = try(aws_db_instance.nexabank.master_user_secret[0].secret_arn, null)
}
