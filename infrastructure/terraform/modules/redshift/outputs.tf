output "cluster_id" {
  description = "Redshift cluster ID"
  value       = aws_redshift_cluster.main.id
}

output "cluster_endpoint" {
  description = "Redshift cluster endpoint"
  value       = aws_redshift_cluster.main.endpoint
}

output "cluster_arn" {
  description = "Redshift cluster ARN"
  value       = aws_redshift_cluster.main.arn
}

output "database_name" {
  description = "Database name"
  value       = aws_redshift_cluster.main.database_name
}
