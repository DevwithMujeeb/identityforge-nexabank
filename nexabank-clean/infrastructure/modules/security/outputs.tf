output "alb_sg_id" {
  description = "ALB security group"
  value       = aws_security_group.alb.id
}

output "bastion_sg_id" {
  description = "Bastion security group"
  value       = aws_security_group.bastion.id
}

output "gateway_sg_id" {
  description = "ECS API gateway security group"
  value       = aws_security_group.gateway.id
}

output "keycloak_sg_id" {
  description = "Keycloak security group"
  value       = aws_security_group.keycloak.id
}

output "ca_sg_id" {
  description = "CA (Smallstep/EJBCA) security group"
  value       = aws_security_group.ca.id
}

output "rds_sg_id" {
  description = "RDS security group (attach to primary and replica)"
  value       = aws_security_group.rds.id
}
