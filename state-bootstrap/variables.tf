variable "aws_s3_bucket" {
  description = "The name of the S3 bucket to store the Terraform state"
  type        = string
  default     = "shopping-state-bucket"
}

variable "region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}