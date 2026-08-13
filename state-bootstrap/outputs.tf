output "state_bucket_name" {
  value       = var.aws_s3_bucket
  description = "The name of the S3 bucket to store the Terraform state"
}

output "state_bucket_arn" {
  value       = aws_s3_bucket.state_bucket.arn
  description = "The ARN of the S3 bucket to store the Terraform state"
}
