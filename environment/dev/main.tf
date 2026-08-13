module "dev_vpc" {
  source      = "../../modules/vpc"
  name        = var.env_name
  cidr_block  = var.vpc_cidr
  environment = var.env_name
}

data "aws_caller_identity" "current" {}

locals {
  ecr_registry         = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  frontend_image       = "${local.ecr_registry}/${var.env_name}-frontend:latest"
  productcatalog_image = "${local.ecr_registry}/${var.env_name}-productcatalogservice:latest"
  cartcheckout_image   = "${local.ecr_registry}/${var.env_name}-cartcheckoutservice:latest"
}

# =================================================================================================
# ECR repositories for the three application images
# =================================================================================================
resource "aws_ecr_repository" "frontend" {
  name                 = "${var.env_name}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "productcatalogservice" {
  name                 = "${var.env_name}-productcatalogservice"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "cartcheckoutservice" {
  name                 = "${var.env_name}-cartcheckoutservice"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# =================================================================================================
# Secrets Manager: DB credentials
# =================================================================================================
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.env_name}/rds/db-credentials"
  description             = "RDS PostgreSQL credentials for cartcheckoutservice"
  recovery_window_in_days = 0 # set to 7+ for production
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

# =================================================================================================
# IAM: lets EC2 instances pull images from ECR and read the DB secret
# =================================================================================================
resource "aws_iam_role" "ec2_ecr_pull" {
  name = "${var.env_name}-ec2-ecr-pull-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_pull" {
  role       = aws_iam_role.ec2_ecr_pull.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy" "ec2_read_db_secret" {
  name = "${var.env_name}-read-db-secret"
  role = aws_iam_role.ec2_ecr_pull.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db_credentials.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_ecr_pull" {
  name = "${var.env_name}-ec2-ecr-pull-profile"
  role = aws_iam_role.ec2_ecr_pull.name
}

# =================================================================================================
# Security groups
#
# Written as bare aws_security_group + aws_vpc_security_group_ingress_rule resources (rather than
# inline ingress blocks or the registry security-group module) so that the internal ALB and the
# cart/checkout instances can reference each other's security group without creating a
# Terraform dependency cycle: each SG is created independently, and the cross-referencing rules
# are separate resources that simply depend on both.
# =================================================================================================

# ----- Public ALB (internet facing) -----
resource "aws_security_group" "alb_public" {
  name        = "${var.env_name}-alb-public-sg"
  description = "Public ALB - internet facing"
  vpc_id      = module.dev_vpc.vpc_id
  tags        = { Name = "${var.env_name}-alb-public-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_public_http" {
  #tfsec:ignore:aws-vpc-no-public-ingress-sgr -- this is the internet-facing entry point by design
  #checkov:skip=CKV_AWS_260: Public ALB must accept inbound HTTP from the internet
  security_group_id = aws_security_group.alb_public.id
  from_port          = 80
  to_port            = 80
  ip_protocol        = "tcp"
  cidr_ipv4          = "0.0.0.0/0"
  description        = "HTTP from anywhere"
}

# ----- Frontend instances (behind the public ALB) -----
resource "aws_security_group" "frontend_instances" {
  name        = "${var.env_name}-frontend-instances-sg"
  description = "Frontend EC2 instances, only reachable via the public ALB"
  vpc_id      = module.dev_vpc.vpc_id
  tags        = { Name = "${var.env_name}-frontend-instances-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id           = aws_security_group.frontend_instances.id
  referenced_security_group_id = aws_security_group.alb_public.id
  from_port                   = 80
  to_port                     = 80
  ip_protocol                 = "tcp"
  description                 = "HTTP from public ALB"
}

resource "aws_vpc_security_group_ingress_rule" "frontend_ssh" {
  security_group_id           = aws_security_group.frontend_instances.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                   = 22
  to_port                     = 22
  ip_protocol                 = "tcp"
  description                 = "SSH from the bastion host only"
}

# ----- Bastion host (public tier) -----
# Reuses the standalone ec2 module for a single small jump box, since the
# app tiers are now private (behind ALBs/ASGs) and no longer directly SSH-able.
resource "aws_security_group" "bastion" {
  name        = "${var.env_name}-bastion-sg"
  description = "Bastion host for SSH access into the private app tier"
  vpc_id      = module.dev_vpc.vpc_id
  tags        = { Name = "${var.env_name}-bastion-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4          = var.admin_cidr
  from_port          = 22
  to_port            = 22
  ip_protocol        = "tcp"
  description        = "SSH from the admin CIDR"
}

# Note: every new security group gets AWS's default "allow all egress" rule
# automatically; we don't manage egress explicitly anywhere in this file so
# that default rule is left in place for all of them.

module "bastion" {
  source            = "../../modules/ec2"
  env               = "${var.env_name}-bastion"
  instance_type     = "t3.micro"
  availability_zone = module.dev_vpc.availability_zones[0]
  subnet_id         = module.dev_vpc.public_subnet_ids[0]
  security_groups   = [aws_security_group.bastion.id]
  key_name          = var.bastion_key_name
}

# ----- Internal ALB (fronts productcatalogservice + cartcheckoutservice) -----
resource "aws_security_group" "internal_alb" {
  name        = "${var.env_name}-internal-alb-sg"
  description = "Internal ALB fronting productcatalogservice and cartcheckoutservice"
  vpc_id      = module.dev_vpc.vpc_id
  tags        = { Name = "${var.env_name}-internal-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_productcatalog_from_frontend" {
  security_group_id           = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.frontend_instances.id
  from_port                   = 3000
  to_port                     = 3000
  ip_protocol                 = "tcp"
  description                 = "productcatalogservice from frontend"
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_cartcheckout_from_frontend" {
  security_group_id           = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.frontend_instances.id
  from_port                   = 3001
  to_port                     = 3001
  ip_protocol                 = "tcp"
  description                 = "cartcheckoutservice from frontend"
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_productcatalog_from_cartcheckout" {
  security_group_id           = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.cartcheckout_instances.id
  from_port                   = 3000
  to_port                     = 3000
  ip_protocol                 = "tcp"
  description                 = "productcatalogservice from cartcheckoutservice"
}

# ----- Product catalog instances (behind the internal ALB) -----
resource "aws_security_group" "productcatalog_instances" {
  name        = "${var.env_name}-productcatalog-instances-sg"
  description = "productcatalogservice EC2 instances, only reachable via the internal ALB"
  vpc_id      = module.dev_vpc.vpc_id
  tags        = { Name = "${var.env_name}-productcatalog-instances-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "productcatalog_from_internal_alb" {
  security_group_id           = aws_security_group.productcatalog_instances.id
  referenced_security_group_id = aws_security_group.internal_alb.id
  from_port                   = 3000
  to_port                     = 3000
  ip_protocol                 = "tcp"
  description                 = "HTTP from internal ALB"
}

resource "aws_vpc_security_group_ingress_rule" "productcatalog_ssh" {
  security_group_id           = aws_security_group.productcatalog_instances.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                   = 22
  to_port                     = 22
  ip_protocol                 = "tcp"
  description                 = "SSH from the bastion host only"
}

# ----- Cart & checkout instances (behind the internal ALB) -----
resource "aws_security_group" "cartcheckout_instances" {
  name        = "${var.env_name}-cartcheckout-instances-sg"
  description = "cartcheckoutservice EC2 instances, only reachable via the internal ALB"
  vpc_id      = module.dev_vpc.vpc_id
  tags        = { Name = "${var.env_name}-cartcheckout-instances-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "cartcheckout_from_internal_alb" {
  security_group_id           = aws_security_group.cartcheckout_instances.id
  referenced_security_group_id = aws_security_group.internal_alb.id
  from_port                   = 3001
  to_port                     = 3001
  ip_protocol                 = "tcp"
  description                 = "HTTP from internal ALB"
}

resource "aws_vpc_security_group_ingress_rule" "cartcheckout_ssh" {
  security_group_id           = aws_security_group.cartcheckout_instances.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                   = 22
  to_port                     = 22
  ip_protocol                 = "tcp"
  description                 = "SSH from the bastion host only"
}

# ===== Security Group for RDS instance ===============================================
module "rds_postgresql_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/postgresql"
  version = "~> 5.0"

  name        = "${var.env_name}-rds-postgresql-sg"
  description = "Security group for RDS PostgreSQL - allows traffic from cartcheckoutservice only"
  vpc_id      = module.dev_vpc.vpc_id

  ingress_rules       = [] # disable default rules
  ingress_cidr_blocks = [] # clear any default CIDRs

  ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "PostgreSQL from cartcheckoutservice instances only"
      source_security_group_id = aws_security_group.cartcheckout_instances.id
    }
  ]

  egress_rules = ["all-all"]

  tags = {
    Name = "${var.env_name}-rds-postgresql-sg"
  }
}

# =================================================================================================
# Load balancers
# =================================================================================================

# ----- Public ALB: internet -> frontend ASG -----
resource "aws_lb" "public" {
  name               = "${var.env_name}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_public.id]
  subnets            = module.dev_vpc.public_subnet_ids
  tags               = { Name = "${var.env_name}-public-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.env_name}-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.dev_vpc.vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.env_name}-frontend-tg" }
}

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ----- Internal ALB: frontend -> productcatalogservice / cartcheckoutservice -----
resource "aws_lb" "internal_services" {
  name               = "${var.env_name}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = module.dev_vpc.private_app_subnet_ids
  tags               = { Name = "${var.env_name}-internal-alb" }
}

resource "aws_lb_target_group" "productcatalog" {
  name        = "${var.env_name}-productcatalog-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.dev_vpc.vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.env_name}-productcatalog-tg" }
}

resource "aws_lb_listener" "productcatalog" {
  load_balancer_arn = aws_lb.internal_services.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.productcatalog.arn
  }
}

resource "aws_lb_target_group" "cartcheckout" {
  name        = "${var.env_name}-cartcheckout-tg"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = module.dev_vpc.vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.env_name}-cartcheckout-tg" }
}

resource "aws_lb_listener" "cartcheckout" {
  load_balancer_arn = aws_lb.internal_services.arn
  port              = 3001
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cartcheckout.arn
  }
}

# =================================================================================================
# Auto Scaling Groups (one per service)
# =================================================================================================

module "frontend_asg" {
  source = "../../modules/asg"

  name                      = "${var.env_name}-frontend"
  instance_type             = var.instance_type
  subnet_ids                = module.dev_vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.frontend_instances.id]
  iam_instance_profile_name = aws_iam_instance_profile.ec2_ecr_pull.name
  target_group_arns         = [aws_lb_target_group.frontend.arn]
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity

  user_data = templatefile("${path.module}/templates/frontend_user_data.sh.tpl", {
    aws_region          = var.region
    ecr_registry        = local.ecr_registry
    image_uri           = local.frontend_image
    product_catalog_url = "http://${aws_lb.internal_services.dns_name}:3000"
    cart_checkout_url   = "http://${aws_lb.internal_services.dns_name}:3001"
    session_secret      = var.session_secret
  })
}

module "product_catalog_asg" {
  source = "../../modules/asg"

  name                      = "${var.env_name}-productcatalog"
  instance_type             = var.instance_type
  subnet_ids                = module.dev_vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.productcatalog_instances.id]
  iam_instance_profile_name = aws_iam_instance_profile.ec2_ecr_pull.name
  target_group_arns         = [aws_lb_target_group.productcatalog.arn]
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity

  user_data = templatefile("${path.module}/templates/productcatalog_user_data.sh.tpl", {
    aws_region   = var.region
    ecr_registry = local.ecr_registry
    image_uri    = local.productcatalog_image
  })
}

module "cart_checkout_asg" {
  source = "../../modules/asg"

  name                      = "${var.env_name}-cartcheckout"
  instance_type             = var.instance_type
  subnet_ids                = module.dev_vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.cartcheckout_instances.id]
  iam_instance_profile_name = aws_iam_instance_profile.ec2_ecr_pull.name
  target_group_arns         = [aws_lb_target_group.cartcheckout.arn]
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity

  user_data = templatefile("${path.module}/templates/cartcheckout_user_data.sh.tpl", {
    aws_region          = var.region
    ecr_registry        = local.ecr_registry
    image_uri           = local.cartcheckout_image
    db_host             = module.dev_rds.db_instance_address
    db_port             = 5432
    db_name             = var.db_name
    db_secret_arn       = aws_secretsmanager_secret.db_credentials.arn
    product_catalog_url = "http://${aws_lb.internal_services.dns_name}:3000"
  })
}

# =================================================================================================
# RDS Postgres
# =================================================================================================
module "dev_rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.env_name}-postgresql"

  # Engine
  engine               = "postgres"
  engine_version       = "16"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = "db.t3.micro"

  # Storage
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  # Credentials — sourced from Secrets Manager at boot; still needed here for
  # initial RDS provisioning. Terraform marks db_password sensitive so it won't
  # appear in plan output.
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  manage_master_user_password = false
  port     = 5432

  # Network — app tier now spans both AZs via ASGs, so we let AWS place RDS
  # within the DB subnet group rather than pinning it to a single AZ
  db_subnet_group_name   = module.dev_vpc.db_subnet_group_name
  vpc_security_group_ids = [module.rds_postgresql_security_group.security_group_id]
  multi_az                = false

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Other settings
  deletion_protection      = false # set to true for production
  skip_final_snapshot      = true  # set to false for production
  delete_automated_backups = true

  tags = {
    Name = "${var.env_name}-postgresql"
  }
}
