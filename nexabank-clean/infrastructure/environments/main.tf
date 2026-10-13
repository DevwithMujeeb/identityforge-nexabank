# NETWORKING

locals {
  name    = "${var.project_name}-${var.environment}"
  is_prod = contains(["prod", "production"], lower(var.environment))
}

module "networking" {
  source = "../modules/networking"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr

  enable_s3_gateway_endpoint = var.enable_s3_gateway_endpoint

  tags = var.tags
}

# SECURITY

module "security" {
  source = "../modules/security"

  project_name = var.project_name
  environment  = var.environment

  # Networking dependency
  vpc_id = module.networking.vpc_id

  # Admin access
  admin_cidr_blocks = var.admin_cidr_blocks

  # Public ALB access
  alb_ingress_cidrs = var.alb_ingress_cidrs

  # ALB HTTP → HTTPS redirect
  enable_http_listener = var.enable_http_listener

  # Service ports
  gateway_port  = var.gateway_port
  keycloak_port = var.keycloak_port
  ca_port       = var.ca_port
  db_port       = var.db_port
  ssh_port      = var.ssh_port

  tags = var.tags
}

# APPLICATION LOAD BALANCER

module "alb" {
  source = "../modules/ALB"

  project_name = var.project_name
  environment  = var.environment

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.alb_subnet_ids

  security_group_id = module.security.alb_sg_id

  gateway_port         = var.gateway_port
  health_check_path    = var.health_check_path
  health_check_matcher = var.health_check_matcher

  certificate_arn = var.certificate_arn
  ssl_policy      = var.ssl_policy

  enable_http_listener = var.enable_http_listener

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout

  access_logs_bucket = module.storage.alb_logs_bucket_id

  tags = var.tags
}


# KMS CMK

module "kms" {
  source = "../modules/kms"

  project_name            = var.project_name
  environment             = var.environment
  deletion_window_in_days = var.deletion_window_in_days

  tags = var.tags
}

# IAM
module "iam" {
  source = "../modules/iam"

  project_name = var.project_name
  environment  = var.environment
  tags         = var.tags
}


# RDS POSTGRESQL

module "rds" {
  source = "../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  db_subnet_group_name = module.networking.db_subnet_group_name
  security_group_id    = module.security.rds_sg_id
  kms_key_arn          = module.kms.rds_key_arn

  az_primary   = module.networking.az_primary
  az_secondary = module.networking.az_secondary

  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  replica_instance_class = var.rds_replica_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  multi_az            = var.rds_multi_az
  create_read_replica = var.rds_create_read_replica

  db_port = var.db_port

  db_name         = var.rds_db_name
  master_username = var.rds_master_username

  backup_retention_period         = var.rds_backup_retention_period
  replica_backup_retention_period = var.rds_replica_backup_retention_period

  backup_window      = var.rds_backup_window
  maintenance_window = var.rds_maintenance_window

  apply_immediately = var.rds_apply_immediately

  deletion_protection = var.rds_deletion_protection

  enable_performance_insights = var.rds_enable_performance_insights
  monitoring_role_arn         = module.iam.rds_monitoring_role_arn
  monitoring_interval         = var.rds_monitoring_interval

  tags = var.tags
}

# COMPUTE

module "bastion" {
  source = "../modules/compute"

  name = "${local.name}-bastion"
  tags = var.tags

  subnet_ids                  = [module.networking.public_subnet_id_primary]
  security_group_ids          = [module.security.bastion_sg_id]
  associate_public_ip_address = true

  instance_type          = var.bastion_instance_type
  ebs_kms_key_arn        = module.kms.ebs_key_arn
  termination_protection = local.is_prod
}

module "keycloak" {
  source = "../modules/compute"

  name = "${local.name}-keycloak"
  tags = var.tags

  # Single subnet until NAT-per-AZ and RDS Multi-AZ exist.
  # Then add module.networking.private_subnet_id_secondary here.
  subnet_ids         = [module.networking.private_subnet_id_primary]
  security_group_ids = [module.security.keycloak_sg_id]

  instance_type           = var.keycloak_instance_type
  ebs_kms_key_arn         = module.kms.ebs_key_arn
  enable_cloudwatch_agent = true

  enable_s3_access  = true
  backup_bucket_arn = module.storage.bucket_arn
  s3_kms_key_arn    = module.kms.s3_key_arn

  termination_protection = local.is_prod

  # Wait for the NAT route so first-boot downloads and SSM registration work
  depends_on = [module.networking]
}

module "ca" {
  source = "../modules/compute"

  name = "${local.name}-ca"
  tags = var.tags

  subnet_ids         = [module.networking.private_subnet_id_primary]
  security_group_ids = [module.security.ca_sg_id]

  instance_type           = var.ca_instance_type
  ebs_kms_key_arn         = module.kms.ebs_key_arn
  enable_cloudwatch_agent = true

  enable_s3_access  = true
  backup_bucket_arn = module.storage.bucket_arn
  s3_kms_key_arn    = module.kms.s3_key_arn

  termination_protection = local.is_prod

  depends_on = [module.networking]
}

# ECS GATEWAY
module "ecs_gateway" {
  source = "../modules/ecs-gateway"

  project_name = var.project_name
  environment  = var.environment
  tags         = var.tags

  # Single subnet for now, to match Keycloak. Add private_subnet_id_secondary for multi-AZ.
  subnet_ids         = [module.networking.private_subnet_id_primary]
  security_group_ids = [module.security.gateway_sg_id]
  target_group_arn   = module.alb.target_group_arn

  execution_role_arn = module.iam.ecs_execution_role_arn
  task_role_arn      = module.iam.ecs_task_role_arn

  container_image = "${module.storage.ecr_repository_url}:${var.gateway_image_tag}"
  container_port  = var.gateway_port

  # The target group must be attached to a listener, and the execution role's
  # policy attached, before the service can start tasks
  depends_on = [module.alb, module.iam]
}

module "storage" {
  source = "../modules/storage"

  name        = local.name
  common_tags = var.tags

  s3_kms_key_arn         = module.kms.s3_key_arn
  create_alb_logs_bucket = true
}
