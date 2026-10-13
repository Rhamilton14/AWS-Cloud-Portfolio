# Alarms answer "is the app up for users?" from the load balancer's point of
# view, which is what a user actually experiences.

resource "aws_sns_topic" "alarms" {
  name = "${var.project}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  tg_dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
  alb_dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}

# Early warning: at least one server is failing health checks.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project}-unhealthy-hosts"
  alarm_description   = "At least one app server is failing ALB health checks for 2 minutes. Check target health reasons."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# Outage: no healthy servers left behind the load balancer.
resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${var.project}-no-healthy-hosts"
  alarm_description   = "Zero healthy app servers. Users are getting errors."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
}

# Errors the load balancer itself returns (502/503/504) when targets fail.
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.project}-elb-5xx"
  alarm_description   = "The load balancer returned more than 5 server errors a minute for 2 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

# Slow responses (p90 over 1 second).
resource "aws_cloudwatch_metric_alarm" "latency" {
  alarm_name          = "${var.project}-p90-latency"
  alarm_description   = "90th percentile response time over 1 second for 3 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dimensions
  extended_statistic  = "p90"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_dashboard" "app" {
  dashboard_name = "${var.project}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Target health"
          region = var.region
          stat   = "Minimum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg_dimensions.TargetGroup, "LoadBalancer", local.tg_dimensions.LoadBalancer],
            [".", "UnHealthyHostCount", ".", ".", ".", ".", { stat = "Maximum" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Requests and errors"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_dimensions.LoadBalancer],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_502_Count", ".", "."],
            [".", "HTTPCode_ELB_503_Count", ".", "."],
            [".", "HTTPCode_ELB_504_Count", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Response time (p50 / p90)"
          region = var.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_dimensions.LoadBalancer, { stat = "p50" }],
            ["...", { stat = "p90" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "App servers: CPU and count"
          region = var.region
          period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name, { stat = "Average" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.app.name, { stat = "Average", yAxis = "right" }],
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 12, width = 24, height = 3
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.no_healthy_hosts.arn,
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.elb_5xx.arn,
            aws_cloudwatch_metric_alarm.latency.arn,
          ]
        }
      },
    ]
  })
}
