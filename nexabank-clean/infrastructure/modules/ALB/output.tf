output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.nexabank.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (for CloudWatch metrics and alarms)"
  value       = aws_lb.nexabank.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name (point your domain's CNAME or alias here)"
  value       = aws_lb.nexabank.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route 53 alias records)"
  value       = aws_lb.nexabank.zone_id
}

output "target_group_arn" {
  description = "Gateway target group ARN (attach the ECS service to this)"
  value       = aws_lb_target_group.gateway.arn
}

output "target_group_arn_suffix" {
  description = "Gateway target group ARN suffix (for CloudWatch)"
  value       = aws_lb_target_group.gateway.arn_suffix
}

output "https_listener_arn" {
  description = "HTTPS listener ARN (null if no certificate)"
  value       = one(aws_lb_listener.https[*].arn)
}

output "http_listener_arn" {
  description = "HTTP listener ARN (null if disabled)"
  value       = one(aws_lb_listener.http[*].arn)
}
