variable "environment" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN"
  type        = string
}

variable "redshift_cluster_id" {
  description = "Redshift cluster identifier"
  type        = string
}
