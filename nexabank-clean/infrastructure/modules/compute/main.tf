# Latest standard Amazon Linux 2023 AMI when ami_id is not provided.
# The filter excludes the minimal and ECS-optimized variants.
data "aws_ami" "al2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023[0].id

  # Each instance may only touch its own prefix in the bucket
  s3_prefix = coalesce(var.s3_key_prefix, var.name)

  s3_object_actions = concat(
    ["s3:GetObject"],
    var.s3_allow_write ? ["s3:PutObject"] : [],
    var.s3_allow_delete ? ["s3:DeleteObject"] : [],
  )

  s3_kms_actions = concat(
    ["kms:Decrypt"],
    var.s3_allow_write ? ["kms:GenerateDataKey"] : [],
  )
}

# IAM
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

# S3 backup access: opt-in, scoped to this instance's own prefix.
data "aws_iam_policy_document" "s3_access" {
  count = var.enable_s3_access ? 1 : 0

  statement {
    sid       = "ListOwnPrefix"
    actions   = ["s3:ListBucket"]
    resources = [var.backup_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.s3_prefix}/*"]
    }
  }

  statement {
    sid       = "ObjectsInOwnPrefix"
    actions   = local.s3_object_actions
    resources = ["${var.backup_bucket_arn}/${local.s3_prefix}/*"]
  }

  # The bucket is encrypted with the S3 KMS key.
  statement {
    sid       = "UseS3KmsKey"
    actions   = local.s3_kms_actions
    resources = [var.s3_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  count = var.enable_s3_access ? 1 : 0

  name   = "${var.name}-s3-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_access[0].json

  lifecycle {
    precondition {
      condition     = var.backup_bucket_arn != "" && var.s3_kms_key_arn != ""
      error_message = "backup_bucket_arn and s3_kms_key_arn are required when enable_s3_access is true."
    }
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.enable_ssm ? 1 : 0

  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count = var.enable_cloudwatch_agent ? 1 : 0

  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = { for i, arn in var.extra_policy_arns : tostring(i) => arn }

  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = var.tags
}

#  Launch template
resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null
  user_data     = var.user_data != null ? base64encode(var.user_data) : null

  # A launch template cannot use both this and a network_interfaces block,
  # so security groups move into the interface when a public IP is requested.
  vpc_security_group_ids = var.associate_public_ip_address == null ? var.security_group_ids : null

  dynamic "network_interfaces" {
    for_each = var.associate_public_ip_address == null ? [] : [1]

    content {
      device_index                = 0
      associate_public_ip_address = var.associate_public_ip_address
      security_groups             = var.security_group_ids
      delete_on_termination       = true
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.metadata_hop_limit
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.ebs_kms_key_arn != "" ? var.ebs_kms_key_arn : null
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-ec2" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-root" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "${var.name}-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = var.subnet_ids # one subnet per AZ; the ASG spreads across them

  target_group_arns         = var.target_group_arns
  health_check_type         = var.health_check_type
  health_check_grace_period = 300

  protect_from_scale_in = var.termination_protection

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.name}-ec2" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
