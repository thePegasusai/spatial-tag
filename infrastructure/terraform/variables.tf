# Environment Configuration
variable "environment" {
  description = "Deployment environment (dev/staging/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# AWS Region Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format: xx-xxxx-#."
  }
}

# VPC Configuration
variable "vpc_config" {
  description = "VPC network configuration parameters"
  type = object({
    cidr_block           = string
    availability_zones   = list(string)
    private_subnets     = list(string)
    public_subnets      = list(string)
    enable_nat_gateway  = bool
    single_nat_gateway  = bool
    enable_vpn_gateway  = bool
  })
  default = {
    cidr_block           = "10.0.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
    private_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    public_subnets      = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
    enable_nat_gateway  = true
    single_nat_gateway  = false
    enable_vpn_gateway  = false
  }
}

# EKS Configuration
variable "eks_config" {
  description = "EKS cluster configuration including version and node groups"
  type = object({
    cluster_version = string
    node_groups = map(object({
      instance_types  = list(string)
      min_size       = number
      max_size       = number
      desired_size   = number
      disk_size      = number
      capacity_type  = string
    }))
    cluster_enabled_log_types = list(string)
    cluster_endpoint_private_access = bool
    cluster_endpoint_public_access  = bool
  })
  default = {
    cluster_version = "1.27"
    node_groups = {
      general = {
        instance_types  = ["t3.large"]
        min_size       = 2
        max_size       = 5
        desired_size   = 3
        disk_size      = 50
        capacity_type  = "ON_DEMAND"
      }
    }
    cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    cluster_endpoint_private_access = true
    cluster_endpoint_public_access  = true
  }
}

# RDS Configuration
variable "rds_config" {
  description = "PostgreSQL RDS configuration parameters"
  type = object({
    instance_class               = string
    allocated_storage           = number
    max_allocated_storage      = number
    multi_az                   = bool
    backup_retention_period    = number
    performance_insights_enabled = bool
    deletion_protection        = bool
    engine_version            = string
    family                    = string
  })
  default = {
    instance_class               = "db.t3.large"
    allocated_storage           = 100
    max_allocated_storage      = 1000
    multi_az                   = true
    backup_retention_period    = 7
    performance_insights_enabled = true
    deletion_protection        = true
    engine_version            = "15.3"
    family                    = "postgres15"
  }
}

# Redis Configuration
variable "redis_config" {
  description = "Redis ElastiCache configuration parameters"
  type = object({
    node_type                  = string
    num_cache_nodes           = number
    parameter_group_family    = string
    automatic_failover_enabled = bool
    multi_az_enabled         = bool
    engine_version           = string
    port                     = number
  })
  default = {
    node_type                  = "cache.t3.medium"
    num_cache_nodes           = 2
    parameter_group_family    = "redis7"
    automatic_failover_enabled = true
    multi_az_enabled         = true
    engine_version           = "7.0"
    port                     = 6379
  }
}

# MongoDB Configuration
variable "mongodb_config" {
  description = "MongoDB DocumentDB configuration parameters"
  type = object({
    instance_class             = string
    replica_count             = number
    backup_retention_period   = number
    preferred_backup_window   = string
    engine_version           = string
    deletion_protection      = bool
    auto_minor_version_upgrade = bool
  })
  default = {
    instance_class             = "db.r5.large"
    replica_count             = 3
    backup_retention_period   = 7
    preferred_backup_window   = "03:00-04:00"
    engine_version           = "5.0"
    deletion_protection      = true
    auto_minor_version_upgrade = true
  }
}

# Resource Tags
variable "tags" {
  description = "Common resource tags to be applied across all infrastructure"
  type        = map(string)
  default = {
    Project     = "SpatialTag"
    ManagedBy   = "Terraform"
    Environment = "dev"
    Owner       = "Platform-Team"
  }
}

# Monitoring Configuration
variable "monitoring_config" {
  description = "Monitoring and logging configuration parameters"
  type = object({
    retention_in_days        = number
    enable_detailed_monitoring = bool
    metrics_granularity     = string
  })
  default = {
    retention_in_days        = 30
    enable_detailed_monitoring = true
    metrics_granularity     = "1Minute"
  }
}