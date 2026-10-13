# Latest Amazon Linux 2023 AMI, looked up at plan time (Python 3 is preinstalled).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app.id]

  # The app code is baked into user data, so any change to app.py or
  # app_version creates a new launch template version, which triggers the
  # Auto Scaling group's rolling instance refresh below. That is the "deploy".
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    app_code    = file("${path.module}/../app/app.py")
    app_port    = var.app_port
    app_version = var.app_version
  }))

  # IMDSv2 only. No instance profile at all: the app calls no AWS APIs,
  # so the servers get no AWS credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.project}-asg"
  min_size            = var.asg_min
  max_size            = var.asg_max
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]

  # Replace instances the load balancer marks unhealthy, not just ones EC2 says are down.
  health_check_type         = "ELB"
  health_check_grace_period = 90

  # Free group metrics, used by the dashboard's server count line.
  enabled_metrics = ["GroupDesiredCapacity", "GroupInServiceInstances"]

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
      # If new instances never pass health checks, put the old version back.
      auto_rollback = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project}-cpu-50"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}
