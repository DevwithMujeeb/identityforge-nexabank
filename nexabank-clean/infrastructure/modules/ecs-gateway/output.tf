output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.nexabank.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.nexabank.arn
}

output "service_name" {
  description = "ECS service name (used by deploy pipelines: aws ecs update-service --force-new-deployment)"
  value       = aws_ecs_service.gateway.name
}

output "task_definition_arn" {
  description = "Current task definition ARN"
  value       = aws_ecs_task_definition.gateway.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the gateway"
  value       = aws_cloudwatch_log_group.gateway.name
}
