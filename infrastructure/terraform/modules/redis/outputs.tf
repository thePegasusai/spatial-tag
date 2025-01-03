# Primary endpoint for Redis cluster write operations
output "primary_endpoint" {
  description = "Primary endpoint address for Redis cluster write operations"
  value       = aws_elasticache_replication_group.spatial_tag.primary_endpoint_address
}

# Reader endpoint for Redis cluster read operations
output "reader_endpoint" {
  description = "Reader endpoint address for Redis cluster read operations"
  value       = aws_elasticache_replication_group.spatial_tag.reader_endpoint_address
}

# Port number for Redis cluster connections
output "port" {
  description = "Port number for Redis cluster connections"
  value       = aws_elasticache_replication_group.spatial_tag.port
}

# Security group ID for Redis cluster access control
output "security_group_id" {
  description = "Security group ID for Redis cluster access control"
  value       = aws_security_group.redis.id
}

# Subnet group name where Redis cluster is deployed
output "subnet_group_name" {
  description = "Name of the subnet group where Redis cluster is deployed"
  value       = aws_elasticache_subnet_group.spatial_tag.name
}

# Redis cluster identifier for reference
output "cluster_id" {
  description = "Identifier of the Redis replication group"
  value       = aws_elasticache_replication_group.spatial_tag.id
}

# Redis configuration endpoint for cluster mode
output "configuration_endpoint" {
  description = "Configuration endpoint for Redis cluster mode operations"
  value       = aws_elasticache_replication_group.spatial_tag.configuration_endpoint_address
}

# Redis cluster ARN for IAM and monitoring
output "cluster_arn" {
  description = "ARN of the Redis replication group for IAM and monitoring"
  value       = aws_elasticache_replication_group.spatial_tag.arn
}

# Redis parameter group name for configuration reference
output "parameter_group_name" {
  description = "Name of the parameter group used by the Redis cluster"
  value       = aws_elasticache_parameter_group.spatial_tag.name
}

# Redis maintenance window for operations planning
output "maintenance_window" {
  description = "Maintenance window for the Redis cluster"
  value       = aws_elasticache_replication_group.spatial_tag.maintenance_window
}