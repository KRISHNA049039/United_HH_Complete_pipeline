terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Research-Data-Platform-V2"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# VPC and Networking
module "vpc" {
  source = "./modules/vpc"
  
  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# S3 Data Lake
module "s3_data_lake" {
  source = "./modules/s3"
  
  environment    = var.environment
  bucket_prefix  = var.bucket_prefix
}

# IAM Roles and Policies
module "iam" {
  source = "./modules/iam"
  
  environment           = var.environment
  s3_bucket_arn        = module.s3_data_lake.bucket_arn
  redshift_cluster_id  = module.redshift.cluster_id
}

# Redshift Cluster
module "redshift" {
  source = "./modules/redshift"
  
  environment             = var.environment
  cluster_identifier      = var.redshift_cluster_identifier
  node_type              = var.redshift_node_type
  number_of_nodes        = var.redshift_number_of_nodes
  database_name          = var.redshift_database_name
  master_username        = var.redshift_master_username
  master_password        = var.redshift_master_password
  subnet_ids             = module.vpc.private_subnet_ids
  vpc_security_group_ids = [module.vpc.redshift_security_group_id]
  iam_role_arn          = module.iam.redshift_role_arn
}

# CloudWatch and SNS
module "monitoring" {
  source = "./modules/monitoring"
  
  environment         = var.environment
  alert_email        = var.alert_email
  redshift_cluster_id = module.redshift.cluster_id
}
