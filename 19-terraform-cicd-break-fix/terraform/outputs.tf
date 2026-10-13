output "app_url" {
  description = "Open this in a browser"
  value       = "http://${aws_lb.web.dns_name}"
}

output "dashboard_url" {
  description = "CloudWatch dashboard for the app"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.app.dashboard_name}"
}

output "app_security_group_id" {
  description = "Used by scripts/break.sh"
  value       = aws_security_group.app.id
}

output "alb_security_group_id" {
  description = "Used by scripts/break.sh"
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "For aws elbv2 describe-target-health"
  value       = aws_lb_target_group.app.arn
}

output "asg_name" {
  description = "Auto Scaling group name"
  value       = aws_autoscaling_group.app.name
}
