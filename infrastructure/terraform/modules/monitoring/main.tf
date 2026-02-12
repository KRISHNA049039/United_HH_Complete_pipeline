# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-research-platform-alerts"

  tags = {
    Name = "${var.environment}-alerts"
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.environment}-validators"
  retention_in_days = 30

  tags = {
    Name = "${var.environment}-lambda-logs"
  }
}

# CloudWatch Log Group for Glue
resource "aws_cloudwatch_log_group" "glue" {
  name              = "/aws/glue/${var.environment}-etl"
  retention_in_days = 30

  tags = {
    Name = "${var.environment}-glue-logs"
  }
}

# CloudWatch Alarm for Redshift CPU
resource "aws_cloudwatch_metric_alarm" "redshift_cpu" {
  alarm_name          = "${var.environment}-redshift-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Redshift CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterIdentifier = var.redshift_cluster_id
  }
}

# CloudWatch Alarm for Redshift Disk Space
resource "aws_cloudwatch_metric_alarm" "redshift_disk" {
  alarm_name          = "${var.environment}-redshift-low-disk"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "PercentageDiskSpaceUsed"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "Redshift disk space is running low"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterIdentifier = var.redshift_cluster_id
  }
}

# CloudWatch Alarm for Redshift Health
resource "aws_cloudwatch_metric_alarm" "redshift_health" {
  alarm_name          = "${var.environment}-redshift-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthStatus"
  namespace           = "AWS/Redshift"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Redshift cluster is unhealthy"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterIdentifier = var.redshift_cluster_id
  }
}

# CloudWatch Alarm for Query Queue Depth
resource "aws_cloudwatch_metric_alarm" "query_queue" {
  alarm_name          = "${var.environment}-redshift-query-queue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "QueueLength"
  namespace           = "AWS/Redshift"
  period              = "300"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "Redshift query queue is too long"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterIdentifier = var.redshift_cluster_id
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-research-platform"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Redshift", "CPUUtilization", { stat = "Average", label = "CPU %" }],
            [".", "PercentageDiskSpaceUsed", { stat = "Average", label = "Disk %" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Redshift Cluster Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Redshift", "DatabaseConnections", { stat = "Sum" }],
            [".", "QueueLength", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Redshift Query Metrics"
        }
      }
    ]
  })
}
