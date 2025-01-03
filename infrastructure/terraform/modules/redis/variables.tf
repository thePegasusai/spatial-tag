variable "environment" {
  type        = string
  description = "Environment name for resource naming and tagging (dev/staging/prod)"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where Redis cluster will be deployed"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for Redis cluster deployment"
}

variable "node_type" {
  type        = string
  description = "Instance type for Redis nodes optimized for spatial data caching"
  default     = "cache.r6g.xlarge" # Optimized for memory-intensive spatial data operations
}

variable "cluster_mode_enabled" {
  type        = bool
  description = "Enable Redis cluster mode for data partitioning"
  default     = true # Enabled by default for better scalability and data distribution
}

variable "num_node_groups" {
  type        = number
  description = "Number of node groups for cluster mode"
  default     = 3 # Default to 3 shards for balanced data distribution
}

variable "replicas_per_node_group" {
  type        = number
  description = "Number of replica nodes in each node group"
  default     = 2 # Default to 2 replicas for high availability
}

variable "port" {
  type        = number
  description = "Port number for Redis cluster connections"
  default     = 6379
}

variable "parameter_group_family" {
  type        = string
  description = "Redis parameter group family (e.g., redis7)"
  default     = "redis7.x" # Latest stable Redis version
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window"
  default     = "sun:05:00-sun:07:00" # Default maintenance window during low-traffic period
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Number of days to retain backups"
  default     = 7 # One week retention for backups
}

variable "tags" {
  type        = map(string)
  description = "Resource tags for Redis cluster and related resources"
  default = {
    "Service"     = "spatial-tag"
    "Component"   = "cache"
    "Managed-by"  = "terraform"
  }
}

# Cache-specific configuration variables
variable "maxmemory_policy" {
  type        = string
  description = "Redis maxmemory-policy for cache eviction strategy"
  default     = "volatile-ttl" # Evict keys with TTL based on TTL value
}

variable "maxmemory_percent" {
  type        = number
  description = "Percentage of memory to use for Redis maxmemory setting"
  default     = 75 # Reserve 25% for Redis overhead
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Enable transit encryption (TLS)"
  default     = true # Enable encryption in transit by default
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true # Enable encryption at rest by default
}

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = true # Enable Multi-AZ for high availability
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover for Multi-AZ"
  default     = true # Enable automatic failover by default
}

variable "notification_topic_arn" {
  type        = string
  description = "SNS topic ARN for Redis notifications"
  default     = "" # Optional SNS topic for notifications
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately or during maintenance window"
  default     = false # Default to applying during maintenance window
}