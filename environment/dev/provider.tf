# environment/dev/provider.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.env_name
      Project     = "terraform-3tier-workshop"
      ManagedBy   = "terraform"
    }
  }
}

