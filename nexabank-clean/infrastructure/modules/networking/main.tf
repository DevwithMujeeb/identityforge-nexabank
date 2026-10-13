data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"

  az_primary   = data.aws_availability_zones.available.names[0] # AZ-1 for main workloads
  az_secondary = data.aws_availability_zones.available.names[1] # AZ-2 for RDS read replica

  cidr_public_primary    = cidrsubnet(var.vpc_cidr, 8, 0)
  cidr_public_secondary  = cidrsubnet(var.vpc_cidr, 8, 1)
  cidr_private_primary   = cidrsubnet(var.vpc_cidr, 8, 10)
  cidr_private_secondary = cidrsubnet(var.vpc_cidr, 8, 11)

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# VPC
resource "aws_vpc" "nexabank" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "nexabank" {
  vpc_id = aws_vpc.nexabank.id

  tags = merge(local.common_tags, { Name = "${local.name}-igw" })
}

# Lock down the VPC default SG to ensure no ingress, no egress, only use provisioned SG

resource "aws_default_security_group" "nexabank" {
  vpc_id = aws_vpc.nexabank.id

  tags = merge(local.common_tags, { Name = "${local.name}-default-sg-locked" })
}

# Public subnets for both AZs, the Regional ALB spans both. AZ-1 also hosts the bastion and NAT Gateway.

resource "aws_subnet" "public_primary" {
  vpc_id                  = aws_vpc.nexabank.id
  availability_zone       = local.az_primary
  cidr_block              = local.cidr_public_primary
  map_public_ip_on_launch = true  # This is for bastion

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-az1"
    Tier = "public"
  })
}

resource "aws_subnet" "public_secondary" {
  vpc_id                  = aws_vpc.nexabank.id
  availability_zone       = local.az_secondary
  cidr_block              = local.cidr_public_secondary
  map_public_ip_on_launch = false  # ALB nodes only

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-az2"
    Tier = "public"
  })
}

# Private subnets for AZ-1 ( Keycloak, Smallstep CA/EJBCA, ECS API gateway, RDS primary )

resource "aws_subnet" "private_primary" {
  vpc_id            = aws_vpc.nexabank.id
  availability_zone = local.az_primary
  cidr_block        = local.cidr_private_primary

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-az1"
    Tier = "private"
  })
}

# Private subnet for AZ-2 RDS read replica only
resource "aws_subnet" "private_secondary" {
  vpc_id            = aws_vpc.nexabank.id
  availability_zone = local.az_secondary
  cidr_block        = local.cidr_private_secondary

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-az2"
    Tier = "private"
  })
}

# RDS subnet group for primary (AZ-1) and replica (AZ-2)

resource "aws_db_subnet_group" "nexabank" {
  name = "${local.name}-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_primary.id,
    aws_subnet.private_secondary.id,
  ]

  tags = merge(local.common_tags, { Name = "${local.name}-db-subnet-group" })
}

# NAT Gateway Single NAT in the AZ-1 public subnet, 

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name}-nat-eip" })

  depends_on = [aws_internet_gateway.nexabank]
}

resource "aws_nat_gateway" "nexabank" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_primary.id

  tags = merge(local.common_tags, { Name = "${local.name}-nat" })

  depends_on = [aws_internet_gateway.nexabank]
}

# Route tables

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.nexabank.id

  tags = merge(local.common_tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.nexabank.id
}

resource "aws_route_table_association" "public_primary" {
  subnet_id      = aws_subnet.public_primary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_secondary" {
  subnet_id      = aws_subnet.public_secondary.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.nexabank.id

  tags = merge(local.common_tags, { Name = "${local.name}-private-rt" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nexabank.id
}

resource "aws_route_table_association" "private_primary" {
  subnet_id      = aws_subnet.private_primary.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_secondary" {
  subnet_id      = aws_subnet.private_secondary.id
  route_table_id = aws_route_table.private.id
}

# S3 gateway endpoint
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.nexabank.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, { Name = "${local.name}-s3-endpoint" })
}

