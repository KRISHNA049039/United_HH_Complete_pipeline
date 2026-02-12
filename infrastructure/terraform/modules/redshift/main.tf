# Redshift Subnet Group
resource "aws_redshift_subnet_group" "main" {
  name       = "${var.environment}-redshift-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.environment}-redshift-subnet-group"
  }
}

# Redshift Parameter Group
resource "aws_redshift_parameter_group" "main" {
  name   = "${var.environment}-redshift-params"
  family = "redshift-1.0"

  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }

  parameter {
    name  = "require_ssl"
    value = "true"
  }

  parameter {
    name  = "max_concurrency_scaling_clusters"
    value = "10"
  }

  tags = {
    Name = "${var.environment}-redshift-params"
  }
}

# Redshift Cluster
resource "aws_redshift_cluster" "main" {
  cluster_identifier  = var.cluster_identifier
  database_name       = var.database_name
  master_username     = var.master_username
  master_password     = var.master_password
  node_type           = var.node_type
  cluster_type        = var.number_of_nodes > 1 ? "multi-node" : "single-node"
  number_of_nodes     = var.number_of_nodes
  
  # Network configuration
  cluster_subnet_group_name    = aws_redshift_subnet_group.main.name
  vpc_security_group_ids       = var.vpc_security_group_ids
  publicly_accessible          = false
  
  # IAM role
  iam_roles = [var.iam_role_arn]
  
  # Parameter group
  cluster_parameter_group_name = aws_redshift_parameter_group.main.name
  
  # Backup and maintenance
  automated_snapshot_retention_period = 7
  preferred_maintenance_window        = "sun:05:00-sun:06:00"
  skip_final_snapshot                 = var.environment != "prod"
  final_snapshot_identifier           = var.environment == "prod" ? "${var.cluster_identifier}-final-snapshot" : null
  
  # Encryption
  encrypted  = true
  kms_key_id = aws_kms_key.redshift.arn
  
  # Enhanced VPC routing
  enhanced_vpc_routing = true
  
  # Logging
  logging {
    enable        = true
    bucket_name   = var.logging_bucket_name
    s3_key_prefix = "redshift-logs/"
  }

  tags = {
    Name = "${var.environment}-redshift-cluster"
  }
}

# KMS Key for Redshift encryption
resource "aws_kms_key" "redshift" {
  description             = "KMS key for Redshift cluster encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "${var.environment}-redshift-kms"
  }
}

resource "aws_kms_alias" "redshift" {
  name          = "alias/${var.environment}-redshift"
  target_key_id = aws_kms_key.redshift.key_id
}

# Redshift Scheduled Action for Auto-scaling
resource "aws_redshift_scheduled_action" "scale_up" {
  name     = "${var.environment}-scale-up"
  schedule = "cron(0 2 ? * MON-FRI *)" # 8 AM IST (2:30 AM UTC)
  iam_role = var.iam_role_arn

  target_action {
    resize_cluster {
      cluster_identifier = aws_redshift_cluster.main.id
      number_of_nodes    = 4
    }
  }
}

resource "aws_redshift_scheduled_action" "scale_down" {
  name     = "${var.environment}-scale-down"
  schedule = "cron(30 12 ? * MON-FRI *)" # 6 PM IST (12:30 PM UTC)
  iam_role = var.iam_role_arn

  target_action {
    resize_cluster {
      cluster_identifier = aws_redshift_cluster.main.id
      number_of_nodes    = var.number_of_nodes
    }
  }
}

# Redshift Scheduled Action for Pause/Resume (cost optimization)
resource "aws_redshift_scheduled_action" "pause_cluster" {
  name     = "${var.environment}-pause-cluster"
  schedule = "cron(0 15 ? * FRI *)" # 8:30 PM IST Friday (3 PM UTC)
  iam_role = var.iam_role_arn

  target_action {
    pause_cluster {
      cluster_identifier = aws_redshift_cluster.main.id
    }
  }
}

resource "aws_redshift_scheduled_action" "resume_cluster" {
  name     = "${var.environment}-resume-cluster"
  schedule = "cron(30 1 ? * MON *)" # 7 AM IST Monday (1:30 AM UTC)
  iam_role = var.iam_role_arn

  target_action {
    resume_cluster {
      cluster_identifier = aws_redshift_cluster.main.id
    }
  }
}
