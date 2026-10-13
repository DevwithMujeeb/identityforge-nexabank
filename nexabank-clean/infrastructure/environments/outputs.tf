# NETWORKING OUTPUTS

output "vpc_id" {
  description = "NexaBank VPC ID"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "NexaBank VPC CIDR"
  value       = module.networking.vpc_cidr
}

output "availability_zones" {
  description = "Availability Zones used by the network"
  value       = module.networking.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs for application and database workloads"
  value       = module.networking.private_subnet_ids
}

output "private_subnet_id_primary" {
  description = "Primary private subnet ID"
  value       = module.networking.private_subnet_id_primary
}

output "private_subnet_id_secondary" {
  description = "Secondary private subnet ID"
  value       = module.networking.private_subnet_id_secondary
}

output "db_subnet_group_name" {
  description = "RDS DB subnet group name"
  value       = module.networking.db_subnet_group_name
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = module.networking.nat_gateway_ids
}

output "nat_public_ips" {
  description = "NAT Gateway public IP addresses"
  value       = module.networking.nat_public_ips
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.networking.internet_gateway_id
}


# SECURITY OUTPUTS

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = module.security.alb_sg_id
}

output "bastion_sg_id" {
  description = "Bastion security group ID"
  value       = module.security.bastion_sg_id
}

output "gateway_sg_id" {
  description = "API gateway security group ID"
  value       = module.security.gateway_sg_id
}

output "keycloak_sg_id" {
  description = "Keycloak security group ID"
  value       = module.security.keycloak_sg_id
}

output "ca_sg_id" {
  description = "CA security group ID"
  value       = module.security.ca_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = module.security.rds_sg_id
}

# KMS CMK

output "kms_key_arns" {
  description = "Map of KMS key purpose to key ARN"
  value       = module.kms.key_arns
}

output "kms_key_ids" {
  description = "Map of KMS key purpose to key ID"
  value       = module.kms.key_ids
}

output "kms_rds_key_arn" {
  description = "KMS key ARN used for RDS encryption"
  value       = module.kms.rds_key_arn
}

output "kms_s3_key_arn" {
  description = "KMS key ARN used for S3 encryption"
  value       = module.kms.s3_key_arn
}

output "kms_ebs_key_arn" {
  description = "KMS key ARN used for EBS encryption"
  value       = module.kms.ebs_key_arn
}

# RDS OUTPUTS

output "rds_primary_endpoint" {
  description = "RDS primary endpoint"
  value       = module.rds.primary_endpoint
}

output "rds_primary_identifier" {
  description = "RDS primary instance identifier"
  value       = module.rds.primary_identifier
}

output "rds_replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = module.rds.replica_endpoint
}

output "rds_replica_identifier" {
  description = "RDS read replica identifier"
  value       = module.rds.replica_identifier
}

output "rds_database_name" {
  description = "Initial RDS database name"
  value       = module.rds.db_name
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN for the RDS master credentials"
  value       = module.rds.master_user_secret_arn
}

output "asg_names" {
  description = "Auto Scaling Group names (find instances with: aws autoscaling describe-auto-scaling-groups)"
  value = {
    bastion  = module.bastion.asg_name
    keycloak = module.keycloak.asg_name
    ca       = module.ca.asg_name
  }
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_gateway.cluster_name
}

output "ecs_service_name" {
  description = "ECS gateway service name"
  value       = module.ecs_gateway.service_name
}
