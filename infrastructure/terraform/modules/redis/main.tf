# AWS Provider version ~> 5.0
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for resource naming and tagging
locals {
  name_prefix = "${var.environment}-spatial-tag-redis"
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Project     = "SpatialTag"
      ManagedBy   = "Terraform"
      Component   = "Redis"
    }
  )
}

# Redis Parameter Group for custom settings
resource "aws_elasticache_parameter_group" "spatial_tag" {
  family = var.parameter_group_family
  name   = "${local.name_prefix}-params"

  # Optimize for spatial data and caching
  parameter {
    name  = "maxmemory-policy"
    value = "volatile-ttl"
  }

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  parameter {
    name  = "maxmemory-samples"
    value = "10"
  }

  parameter {
    name  = "lazyfree-lazy-eviction"
    value = "yes"
  }

  tags = local.common_tags
}

# Redis Subnet Group
resource "aws_elasticache_subnet_group" "spatial_tag" {
  name       = "${local.name_prefix}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = local.common_tags
}

# Security Group for Redis Cluster
resource "aws_security_group" "redis" {
  name_prefix = "${local.name_prefix}-sg-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "Redis access from application layer"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Redis Replication Group
resource "aws_elasticache_replication_group" "spatial_tag" {
  replication_group_id = "${local.name_prefix}-cluster"
  description         = "Redis cluster for Spatial Tag application"

  node_type = var.node_type
  port      = 6379

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = true
  multi_az_enabled          = true

  parameter_group_name = aws_elasticache_parameter_group.spatial_tag.name
  subnet_group_name    = aws_elasticache_subnet_group.spatial_tag.name
  security_group_ids   = [aws_security_group.redis.id]

  maintenance_window = var.maintenance_window
  snapshot_window   = var.backup_window

  snapshot_retention_limit = var.backup_retention_period

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  auto_minor_version_upgrade = true

  # Configure notification and monitoring
  notification_topic_arn = var.sns_topic_arn

  # Apply custom tags
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-cluster"
    }
  )

  # Advanced configurations
  log_delivery_configuration {
    destination      = var.cloudwatch_log_group_name
    destination_type = "cloudwatch-logs"
    log_format      = "json"
    log_type        = "slow-log"
  }

  log_delivery_configuration {
    destination      = var.cloudwatch_log_group_name
    destination_type = "cloudwatch-logs"
    log_format      = "json"
    log_type        = "engine-log"
  }
}

# CloudWatch Alarms for Redis Monitoring
resource "aws_cloudwatch_metric_alarm" "cache_cpu" {
  alarm_name          = "${local.name_prefix}-cpu-utilization"
  alarm_description   = "Redis cluster CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CPUUtilization"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "75"

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.spatial_tag.id
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cache_memory" {
  alarm_name          = "${local.name_prefix}-memory-utilization"
  alarm_description   = "Redis cluster memory utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "DatabaseMemoryUsagePercentage"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "80"

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.spatial_tag.id
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cache_connections" {
  alarm_name          = "${local.name_prefix}-connections"
  alarm_description   = "Redis cluster connection count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "CurrConnections"
  namespace          = "AWS/ElastiCache"
  period             = "300"
  statistic          = "Average"
  threshold          = "5000"

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.spatial_tag.id
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = local.common_tags
}