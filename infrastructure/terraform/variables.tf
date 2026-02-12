variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-south-1" # Mumbai region for India-focused firm
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for multi-AZ deployment"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "itus-capital-data"
}

variable "redshift_cluster_identifier" {
  description = "Redshift cluster identifier"
  type        = string
  default     = "itus-research-platform"
}

variable "redshift_node_type" {
  description = "Redshift node type"
  type        = string
  default     = "ra3.4xlarge"
}

variable "redshift_number_of_nodes" {
  description = "Number of Redshift nodes"
  type        = number
  default     = 2
}

variable "redshift_database_name" {
  description = "Redshift database name"
  type        = string
  default     = "research_platform"
}

variable "redshift_master_username" {
  description = "Redshift master username"
  type        = string
  sensitive   = true
}

variable "redshift_master_password" {
  description = "Redshift master password"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
}
