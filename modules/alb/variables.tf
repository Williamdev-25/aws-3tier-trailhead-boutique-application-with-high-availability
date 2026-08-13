variable "name" {
  description = "Name for the load balancer and its target group"
  type        = string
}

variable "internal" {
  description = "Whether this ALB is internal (no public IP) or internet-facing"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC to create the target group in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets to place the load balancer in (at least 2, in different AZs)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups to attach to the load balancer"
  type        = list(string)
}

variable "target_port" {
  description = "Port that backend instances listen on"
  type        = number
}

variable "health_check_path" {
  description = "HTTP path used for target group health checks"
  type        = string
  default     = "/health"
}
