variable "instance_type" {
  description = "The type of instance to use"
  type        = string
  default     = "t2.micro"
  
}

variable "availability_zone" {
  description = "The availability zone to launch the instance in"
  type        = string
 
}

variable "subnet_id" {
  description = "The ID of the subnet to launch the instance in"
  type        = string
}

variable "security_groups" {
  description = "The IDs of the security groups to associate with the instance"
  type        = list(string)
}

variable "env" {
  description = "The environment to deploy the instance in"
  type        = string
}

variable "user_data" {
  description = "Optional cloud-init / shell script to run on instance boot"
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "Optional IAM instance profile name to attach (e.g. for ECR pull access)"
  type        = string
  default     = null
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access"
  type        = string
  default     = null
}