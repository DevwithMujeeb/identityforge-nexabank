locals {
  name          = "${var.project_name}-${var.environment}"
  https_enabled = var.certificate_arn != null

  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ALB
resource "aws_lb" "nexabank" {
  name               = "${local.name}-alb"  
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [var.access_logs_bucket] : []

    content {
      bucket  = access_logs.value
      prefix  = "alb"
      enabled = true
    }
  }

  lifecycle {
    precondition {
      condition     = local.https_enabled || var.enable_http_listener
      error_message = "The ALB needs at least one listener, set certificate_arn or enable_http_listener."
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name}-alb" })
}

# Target group (ECS gateway) 

resource "aws_lb_target_group" "gateway" {
  name_prefix = "gwtg-"
  port        = var.gateway_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "${local.name}-gateway-tg" })
}

# Listeners
resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.nexabank.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  count = var.enable_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.nexabank.arn
  port              = 80
  protocol          = "HTTP"

  # With a certificate: redirect to HTTPS

  dynamic "default_action" {
    for_each = local.https_enabled ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  # Without a certificate forward straight to the gateway (dev only)

  dynamic "default_action" {
    for_each = local.https_enabled ? [] : [1]

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.gateway.arn
    }
  }

  tags = local.common_tags
}

