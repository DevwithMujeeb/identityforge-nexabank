output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.app.arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.app.id
}

output "iam_role_name" {
  description = "Name of the instance IAM role (attach extra policies to this from the root)."
  value       = aws_iam_role.ec2.name
}

output "iam_role_arn" {
  description = "ARN of the instance IAM role."
  value       = aws_iam_role.ec2.arn
}

output "instance_profile_name" {
  description = "Name of the instance profile."
  value       = aws_iam_instance_profile.ec2.name
}
