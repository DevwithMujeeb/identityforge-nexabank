output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.nexabank.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.nexabank.cidr_block
}

output "az_primary" {
  description = "AZ-1 (main workloads)"
  value       = local.az_primary
}

output "az_secondary" {
  description = "AZ-2 (RDS read replica)"
  value       = local.az_secondary
}

output "alb_subnet_ids" {
  description = "Public subnets for the ALB (AZ-1, plus the AZ-2)"
  value       = concat([aws_subnet.public_primary.id], [aws_subnet.public_secondary.id])
}

output "public_subnet_id_primary" {
  description = "AZ-1 public subnet (bastion, NAT, ALB)"
  value       = aws_subnet.public_primary.id
}

output "public_subnet_id_secondary" {
  description = "AZ-2 public subnet (ALB)"
  value       = aws_subnet.public_secondary.id
}

output "private_subnet_id_primary" {
  description = "AZ-1 private subnet (Keycloak, CA, ECS, RDS primary)"
  value       = aws_subnet.private_primary.id
}

output "private_subnet_id_secondary" {
  description = "AZ-2 private subnet (RDS read replica)"
  value       = aws_subnet.private_secondary.id
}

output "db_subnet_group_name" {
  description = "DB subnet group for the RDS primary and read replica"
  value       = aws_db_subnet_group.nexabank.name
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = [aws_nat_gateway.nexabank.id]
}

output "nat_public_ips" {
  description = "List of NAT Gateway public EIPs (for third-party IP allow-listing)"
  value       = [aws_eip.nat.public_ip]
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.nexabank.id
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = aws_route_table.private.id
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

output "availability_zones" {
  description = "List of Availability Zones used by subnets"
  value       = [local.az_primary, local.az_secondary]
}

output "public_subnet_ids" {
  description = "List of all public subnet IDs"
  value       = [aws_subnet.public_primary.id, aws_subnet.public_secondary.id]
}

output "private_subnet_ids" {
  description = "List of all private subnet IDs"
  value       = [aws_subnet.private_primary.id, aws_subnet.private_secondary.id]
}
