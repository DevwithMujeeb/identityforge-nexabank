data "aws_region" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  container_definition = merge(
    {
      name      = var.container_name
      image     = var.container_image
      essential = true

      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      environment = [for k, v in var.environment_variables : { name = k, value = v }]
      secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]

      readonlyRootFilesystem = var.readonly_root_filesystem

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.gateway.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "gateway"
        }
      }
    },
    var.container_health_check_command == null ? {} : {
      healthCheck = {
        command     = var.container_health_check_command
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    }
  )
}

# Cluster
resource "aws_ecs_cluster" "nexabank" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, { Name = "${local.name}-cluster" })
}

# Logs
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/ecs/${local.name}/gateway"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, { Name = "${local.name}-gateway-logs" })
}

# Task definition
resource "aws_ecs_task_definition" "gateway" {
  family                   = "${local.name}-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([local.container_definition])

  tags = merge(local.common_tags, { Name = "${local.name}-gateway-task" })
}

# Service
resource "aws_ecs_service" "gateway" {
  name            = "${local.name}-gateway"
  cluster         = aws_ecs_cluster.nexabank.id
  task_definition = aws_ecs_task_definition.gateway.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  enable_execute_command            = var.enable_execute_command
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # A bad release (for example a missing health route) stops and rolls back
  # instead of restarting tasks in a loop.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  tags = merge(local.common_tags, { Name = "${local.name}-gateway" })

  lifecycle {
    # Capacity is owned by autoscaling after creation
    ignore_changes = [desired_count]
  }
}

# Autoscaling
resource "aws_appautoscaling_target" "gateway" {
  count = var.enable_autoscaling ? 1 : 0

  min_capacity       = var.autoscaling_min_capacity
  max_capacity       = var.autoscaling_max_capacity
  resource_id        = "service/${aws_ecs_cluster.nexabank.name}/${aws_ecs_service.gateway.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  lifecycle {
    precondition {
      condition     = var.autoscaling_max_capacity >= var.autoscaling_min_capacity
      error_message = "autoscaling_max_capacity must be greater than or equal to autoscaling_min_capacity."
    }
  }
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${local.name}-gateway-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.gateway[0].resource_id
  scalable_dimension = aws_appautoscaling_target.gateway[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.gateway[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
