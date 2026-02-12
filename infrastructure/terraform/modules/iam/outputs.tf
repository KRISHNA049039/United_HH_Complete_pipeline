output "redshift_role_arn" {
  description = "Redshift IAM role ARN"
  value       = aws_iam_role.redshift.arn
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda.arn
}

output "glue_role_arn" {
  description = "Glue IAM role ARN"
  value       = aws_iam_role.glue.arn
}
