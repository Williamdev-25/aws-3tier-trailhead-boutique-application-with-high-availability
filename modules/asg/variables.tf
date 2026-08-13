variable "name" {
  description = "Name prefix used for the launch template and ASG"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type to launch"
  type        = string
  default     = "t3.micro"
}

variable "subnet_ids" {
  description = "Subnets the ASG should launch instances into (one per AZ for HA)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs to attach to each instance"
  type        = list(string)
}

variable "iam_instance_profile_name" {
  description = "Optional IAM instance profile name (e.g. for ECR pull access)"
  type        = string
  default     = null
}

variable "user_data" {
  description = "Plain-text user_data script; this module base64-encodes it"
  type        = string
}

variable "target_group_arns" {
  description = "ALB target group ARNs to register instances with"
  type        = list(string)
  default     = []
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "health_check_grace_period" {
  description = "Seconds to wait after instance launch before checking ALB health (allow time for docker pull + app boot)"
  type        = number
  default     = 90
}
