# General

aws_region = "af-south-1"

project_name = "nexabank"
environment  = "prod"

tags = {
  Owner = "identity-forge"
}

# Networking

vpc_cidr                   = "10.0.0.0/16"
enable_s3_gateway_endpoint = true

# Security

# Admin access to the bastion
admin_cidr_blocks = ["203.0.113.0/28"] # We need to replace with admin Ip

# Public application traffic
alb_ingress_cidrs = ["0.0.0.0/0"]

# Port 80 allows the ALB to redirect HTTP to HTTPS when a certificate exists.
enable_http_listener = true

# Service ports
gateway_port  = 3000
keycloak_port = 8443
ca_port       = 9000 # Smallstep CA; use 8443 for EJBCA
db_port       = 5432
ssh_port      = 22

#  ALB
certificate_arn = "arn:aws:acm:af-south-1:<account-id>:certificate/<id>" #replace with real cert ARN

ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

enable_deletion_protection = true
idle_timeout               = 60
health_check_path          = "/health"
health_check_matcher       = "200-399"


# KMS
deletion_window_in_days = 30


# RDS

rds_engine_version = "17"

rds_instance_class         = "db.t3.micro"
rds_replica_instance_class = "db.t3.micro"

rds_allocated_storage     = 20
rds_max_allocated_storage = 100

rds_multi_az            = false
rds_create_read_replica = true

rds_db_name         = "nexabank"
rds_master_username = "nexabank_admin"

rds_backup_retention_period         = 14
rds_replica_backup_retention_period = 7

rds_backup_window      = "02:00-03:00"
rds_maintenance_window = "sun:03:30-sun:04:30"

rds_apply_immediately   = false
rds_deletion_protection = true

rds_enable_performance_insights = true
rds_monitoring_role_arn         = null
rds_monitoring_interval         = 60

# Compute

bastion_instance_type  = "t3.small" # SSH/SSM jump host, light load
keycloak_instance_type = "t3.large" # JVM app: 2 vCPU, 8 GiB. t3.medium (4 GiB) is the floor
ca_instance_type       = "t3.small" # Smallstep CA is light; EJBCA needs more (t3.large)

# ECS gateway
gateway_image_tag = "1.0.0"
