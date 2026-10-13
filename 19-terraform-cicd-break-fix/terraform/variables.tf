variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for every resource"
  type        = string
  default     = "tf-webapp"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.19.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the app servers"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the app listens on inside the VPC"
  type        = number
  default     = 8080
}

variable "app_version" {
  description = "Shown on the home page. Bump it to watch the pipeline roll out a new version."
  type        = string
  default     = "v1"
}

variable "asg_min" {
  description = "Minimum app servers. 2 keeps one in each AZ."
  type        = number
  default     = 2
}

variable "asg_max" {
  description = "Maximum app servers the target tracking policy can scale out to"
  type        = number
  default     = 4
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications. Leave empty to skip the subscription."
  type        = string
  default     = ""
}
