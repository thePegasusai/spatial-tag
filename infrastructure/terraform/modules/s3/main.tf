# AWS S3 Module for Spatial Tag Platform
# Provider version: ~> 5.0

# Main S3 bucket resource
resource "aws_s3_bucket" "media_storage" {
  bucket = "${var.environment}-${var.bucket_name}"
  
  # Force destroy only in non-production environments
  force_destroy = var.environment != "prod"

  tags = merge({
    Name        = "${var.environment}-${var.bucket_name}"
    Environment = var.environment
    Service     = "spatial-tag"
    Managed_by  = "terraform"
  }, var.tags)
}

# Versioning configuration
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.media_storage.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.media_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_configuration.sse_algorithm
      kms_master_key_id = var.encryption_configuration.kms_master_key_id
    }
    bucket_key_enabled = true
  }
}

# Lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.media_storage.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transition_days != null ? [1] : []
        content {
          days          = rule.value.transition_days
          storage_class = rule.value.transition_storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }
    }
  }
}

# CORS configuration
resource "aws_s3_bucket_cors_configuration" "cors" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.media_storage.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# Public access block configuration
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.media_storage.id

  block_public_acls       = var.public_access_block.block_public_acls
  block_public_policy     = var.public_access_block.block_public_policy
  ignore_public_acls      = var.public_access_block.ignore_public_acls
  restrict_public_buckets = var.public_access_block.restrict_public_buckets
}

# Replication configuration
resource "aws_s3_bucket_replication_configuration" "replication" {
  count  = var.replication_configuration.replication_enabled ? 1 : 0
  bucket = aws_s3_bucket.media_storage.id
  role   = var.replication_configuration.role

  rule {
    id     = "media-replication"
    status = "Enabled"

    destination {
      bucket        = var.replication_configuration.destination_bucket_arn
      storage_class = var.replication_configuration.replica_storage_class

      dynamic "encryption_configuration" {
        for_each = var.encryption_configuration.sse_algorithm == "aws:kms" ? [1] : []
        content {
          replica_kms_key_id = var.encryption_configuration.kms_master_key_id
        }
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = var.encryption_configuration.sse_algorithm == "aws:kms" ? "Enabled" : "Disabled"
      }
    }
  }
}

# Access logging configuration
resource "aws_s3_bucket_logging" "access_logging" {
  bucket = aws_s3_bucket.media_storage.id

  target_bucket = aws_s3_bucket.media_storage.id
  target_prefix = "access-logs/"
}

# Metrics configuration for monitoring
resource "aws_s3_bucket_metric" "metrics" {
  bucket = aws_s3_bucket.media_storage.id
  name   = "EntireBucket"

  filter {
    prefix = ""
    tags   = {}
  }
}

# Bucket policy for secure access
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.media_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.media_storage.arn,
          "${aws_s3_bucket.media_storage.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}