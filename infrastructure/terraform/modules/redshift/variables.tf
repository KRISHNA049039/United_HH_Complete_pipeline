variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_identifier" {
  description = "Redshift cluster identifier"
  type        = string
}

variable "database_name" {
  description = "Database name"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "node_type" {
  description = "Node type"
  type        = string
}

variable "number_of_nodes" {
  description = "Number of nodes"
  type        = number
}

variable "subnet_ids" {
  description = "Subnet IDs for Redshift"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "VPC security group IDs"
  type        = list(string)
}

variable "iam_role_arn" {
  description = "IAM role ARN for Redshift"
  type        = string
}

variable "logging_bucket_name" {
  description = "S3 bucket name for logging"
  type        = string
  default     = ""
}
