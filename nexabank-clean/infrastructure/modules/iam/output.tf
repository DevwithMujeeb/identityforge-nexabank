output "rds_monitoring_role_arn" {
  description = "RDS Enhanced Monitoring role ARN (null if not created). Pass to the rds module as monitoring_role_arn."
  value       = one(aws_iam_role.rds_monitoring[*].arn)
}

output "ecs_execution_role_arn" {
  description = "ECS task execution role ARN (null if not created)"
  value       = one(aws_iam_role.ecs_execution[*].arn)
}

output "ecs_execution_role_name" {
  description = "ECS task execution role name (null if not created)"
  value       = one(aws_iam_role.ecs_execution[*].name)
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN (null if not created)"
  value       = one(aws_iam_role.ecs_task[*].arn)
}

output "ecs_task_role_name" {
  description = "ECS task role name (null if not created)"
  value       = one(aws_iam_role.ecs_task[*].name)
}
