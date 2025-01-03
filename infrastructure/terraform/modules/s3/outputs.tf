# S3 bucket identifier output
output "bucket_id" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.media_storage.id
}

# S3 bucket ARN output
output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.media_storage.arn
}

# S3 bucket domain name output
output "bucket_domain_name" {
  description = "The domain name of the S3 bucket for direct access"
  value       = aws_s3_bucket.media_storage.bucket_domain_name
}

# S3 bucket regional domain name output
output "bucket_regional_domain_name" {
  description = "The regional domain name of the S3 bucket for CDN origin configuration"
  value       = aws_s3_bucket.media_storage.bucket_regional_domain_name
}

# S3 bucket versioning status output
output "versioning_status" {
  description = "The versioning status of the S3 bucket"
  value       = aws_s3_bucket_versioning.versioning.versioning_configuration[0].status
}

# S3 bucket encryption configuration output
output "encryption_configuration" {
  description = "The server-side encryption configuration of the S3 bucket"
  value = {
    algorithm        = aws_s3_bucket_server_side_encryption_configuration.encryption.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm
    kms_master_key_id = aws_s3_bucket_server_side_encryption_configuration.encryption.rule[0].apply_server_side_encryption_by_default[0].kms_master_key_id
  }
  sensitive = true
}

# S3 bucket region output
output "bucket_region" {
  description = "The AWS region where the S3 bucket is located"
  value       = data.aws_region.current.name
}

# S3 bucket website endpoint (if configured)
output "website_endpoint" {
  description = "The website endpoint of the S3 bucket, if static website hosting is enabled"
  value       = try(aws_s3_bucket.media_storage.website_endpoint, null)
}

# S3 bucket replication status
output "replication_status" {
  description = "The status of cross-region replication for the S3 bucket"
  value       = try(aws_s3_bucket_replication_configuration.replication[0].rule[0].status, "Disabled")
}

# S3 bucket logging configuration
output "logging_configuration" {
  description = "The logging configuration of the S3 bucket"
  value = {
    target_bucket = aws_s3_bucket_logging.access_logging.target_bucket
    target_prefix = aws_s3_bucket_logging.access_logging.target_prefix
  }
}

# S3 bucket CORS configuration
output "cors_rules" {
  description = "The CORS configuration rules of the S3 bucket"
  value       = try(aws_s3_bucket_cors_configuration.cors[0].cors_rule, [])
}

# S3 bucket lifecycle rules
output "lifecycle_rules" {
  description = "The lifecycle rules configured for the S3 bucket"
  value       = try(aws_s3_bucket_lifecycle_configuration.lifecycle[0].rule, [])
}

# S3 bucket public access block configuration
output "public_access_block" {
  description = "The public access block configuration of the S3 bucket"
  value = {
    block_public_acls       = aws_s3_bucket_public_access_block.public_access.block_public_acls
    block_public_policy     = aws_s3_bucket_public_access_block.public_access.block_public_policy
    ignore_public_acls      = aws_s3_bucket_public_access_block.public_access.ignore_public_acls
    restrict_public_buckets = aws_s3_bucket_public_access_block.public_access.restrict_public_buckets
  }
}