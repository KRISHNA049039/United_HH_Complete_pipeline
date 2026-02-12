output "redshift_cluster_endpoint" {
  description = "Redshift cluster endpoint"
  value       = module.redshift.cluster_endpoint
  sensitive   = true
}

output "redshift_database_name" {
  description = "Redshift database name"
  value       = module.redshift.database_name
}

output "s3_bucket_name" {
  description = "S3 data lake bucket name"
  value       = module.s3_data_lake.bucket_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = module.monitoring.sns_topic_arn
}

output "iam_role_arns" {
  description = "IAM role ARNs"
  value = {
    redshift = module.iam.redshift_role_arn
    lambda   = module.iam.lambda_role_arn
    glue     = module.iam.glue_role_arn
  }
}
