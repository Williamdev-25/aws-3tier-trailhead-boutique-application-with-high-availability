variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "env_name" {
  description = "The name prefix for resources"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "PostgreSQL master username — used to provision RDS and stored in Secrets Manager"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "PostgreSQL master password — used to provision RDS and stored in Secrets Manager; instances fetch it from there at boot"
  type        = string
  sensitive   = true
}

variable "session_secret" {
  description = "Secret used to sign the frontend's session cookie"
  type        = string
  sensitive   = true
  default     = "change-me-in-a-real-deployment"
}

variable "instance_type" {
  description = "EC2 instance type used by every ASG"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum instances per service ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum instances per service ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired instances per service ASG"
  type        = number
  default     = 2
}

variable "admin_cidr" {
  description = "CIDR block allowed to SSH into the bastion host (defaults to VPC-internal only; set to your own IP, e.g. 203.0.113.4/32, for external access)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "bastion_key_name" {
  description = "Existing EC2 key pair name for SSH access to the bastion host"
  type        = string
  default     = null
}