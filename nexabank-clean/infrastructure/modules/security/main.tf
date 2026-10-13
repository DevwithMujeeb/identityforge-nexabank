locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  sg_ids = {
    alb      = aws_security_group.alb.id
    bastion  = aws_security_group.bastion.id
    gateway  = aws_security_group.gateway.id
    keycloak = aws_security_group.keycloak.id
    ca       = aws_security_group.ca.id
    rds      = aws_security_group.rds.id
  }

  # Each entry creates an egress rule on "from" and a matching ingress rule on "to".
  flows = {

    # User path from ALB to API gateway to Keycloak / RDS

    alb_to_gateway      = { from = "alb", to = "gateway", port = var.gateway_port, description = "ALB to API gateway" }
    gateway_to_keycloak = { from = "gateway", to = "keycloak", port = var.keycloak_port, description = "API gateway to Keycloak" }
    gateway_to_rds      = { from = "gateway", to = "rds", port = var.db_port, description = "API gateway to PostgreSQL" }

    # Service to service
    keycloak_to_rds = { from = "keycloak", to = "rds", port = var.db_port, description = "Keycloak to PostgreSQL" }
    keycloak_to_ca  = { from = "keycloak", to = "ca", port = var.ca_port, description = "Keycloak to CA" }
    ca_to_rds       = { from = "ca", to = "rds", port = var.db_port, description = "CA to PostgreSQL (EJBCA)" }

    # Admin path (bastion only)
    bastion_to_keycloak_admin = { from = "bastion", to = "keycloak", port = var.keycloak_port, description = "Bastion to Keycloak admin console" }
    bastion_to_keycloak_ssh   = { from = "bastion", to = "keycloak", port = var.ssh_port, description = "Bastion SSH to Keycloak hosts" }
    bastion_to_ca             = { from = "bastion", to = "ca", port = var.ca_port, description = "Bastion to CA admin" }
    bastion_to_ca_ssh         = { from = "bastion", to = "ca", port = var.ssh_port, description = "Bastion SSH to CA hosts" }
    bastion_to_rds            = { from = "bastion", to = "rds", port = var.db_port, description = "Bastion to PostgreSQL admin" }
  }

  # Outbound internet via NAT 
  internet_egress = {
    bastion_https  = { sg = "bastion", port = 443, description = "Bastion HTTPS out" }
    bastion_http   = { sg = "bastion", port = 80, description = "Bastion HTTP out for OS updates" }
    gateway_https  = { sg = "gateway", port = 443, description = "API gateway HTTPS out (ECR, AWS APIs)" }
    keycloak_https = { sg = "keycloak", port = 443, description = "Keycloak HTTPS out (updates, AWS APIs)" }
    ca_https       = { sg = "ca", port = 443, description = "CA HTTPS out (updates, KMS, S3)" }
  }
}

# Security groups
# rules

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Public ALB for user traffic"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-alb-sg" })
}

resource "aws_security_group" "bastion" {
  name        = "${local.name}-bastion-sg"
  description = "Bastion host - admin entry point"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-bastion-sg" })
}

resource "aws_security_group" "gateway" {
  name        = "${local.name}-gateway-sg"
  description = "ECS API gateway (APISIX or Kong)"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-gateway-sg" })
}

resource "aws_security_group" "keycloak" {
  name        = "${local.name}-keycloak-sg"
  description = "Keycloak EC2 instances"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-keycloak-sg" })
}

resource "aws_security_group" "ca" {
  name        = "${local.name}-ca-sg"
  description = "Smallstep CA or EJBCA EC2 instances"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-ca-sg" })
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "RDS PostgreSQL primary and read replica"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = "${local.name}-rds-sg" })
}

# Edge (users to ALB )
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from users"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = var.enable_http_listener ? toset(var.alb_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from users for redirect to HTTPS"
}

# Edge (admins to bastion (SSH only))

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.admin_cidr_blocks)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  description       = "SSH from admin"
}

# Internal SG-to-SG flows
resource "aws_vpc_security_group_egress_rule" "flow" {
  for_each = local.flows

  security_group_id            = local.sg_ids[each.value.from]
  referenced_security_group_id = local.sg_ids[each.value.to]
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "flow" {
  for_each = local.flows

  security_group_id            = local.sg_ids[each.value.to]
  referenced_security_group_id = local.sg_ids[each.value.from]
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

#  Outbound internet
resource "aws_vpc_security_group_egress_rule" "internet" {
  for_each = local.internet_egress

  security_group_id = local.sg_ids[each.value.sg]
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.description
}
