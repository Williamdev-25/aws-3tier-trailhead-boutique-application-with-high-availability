output "vpc_id" {
  value = module.dev_vpc.vpc_id
}

output "frontend_url" {
  description = "Public URL of the storefront (via the public ALB)"
  value       = "http://${aws_lb.public.dns_name}"
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB fronting productcatalogservice and cartcheckoutservice"
  value       = aws_lb.internal_services.dns_name
}

output "frontend_asg_name" {
  value = module.frontend_asg.asg_name
}

output "product_catalog_asg_name" {
  value = module.product_catalog_asg.asg_name
}

output "cart_checkout_asg_name" {
  value = module.cart_checkout_asg.asg_name
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host (SSH jump box into the private app tier)"
  value       = module.bastion.server_public_ip
}

output "rds_endpoint" {
  value = module.dev_rds.db_instance_address
}

output "ecr_frontend_repo_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_productcatalog_repo_url" {
  value = aws_ecr_repository.productcatalogservice.repository_url
}

output "ecr_cartcheckout_repo_url" {
  value = aws_ecr_repository.cartcheckoutservice.repository_url
}
