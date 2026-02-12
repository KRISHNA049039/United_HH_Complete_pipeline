# S3 Bucket for Data Lake
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.bucket_prefix}-lake-${var.environment}"

  tags = {
    Name        = "${var.environment}-data-lake"
    Purpose     = "Raw and processed data storage"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  # Archive raw files after 90 days
  rule {
    id     = "archive-raw-files"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  # Delete processed files after 180 days
  rule {
    id     = "delete-processed-files"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    expiration {
      days = 180
    }
  }

  # Archive old data after 2 years
  rule {
    id     = "archive-old-data"
    status = "Enabled"

    filter {
      prefix = "archive/"
    }

    transition {
      days          = 730
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# S3 Event Notifications (will be configured with Lambda)
resource "aws_s3_bucket_notification" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  # Placeholder - Lambda functions will be added in Task 2
}
