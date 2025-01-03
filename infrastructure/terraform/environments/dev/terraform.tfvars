# Environment Identifier
environment = "dev"

# AWS Region
aws_region = "us-east-1"

# VPC Configuration
vpc_config = {
  cidr_block           = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets      = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = true
  enable_vpn_gateway  = false
}

# EKS Configuration - Development Sized
eks_config = {
  cluster_version = "1.27"
  node_groups = {
    general = {
      instance_types  = ["t3.medium"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size      = 50
      capacity_type  = "ON_DEMAND"
    }
  }
  cluster_enabled_log_types       = ["api", "audit"]
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
}

# RDS Configuration - Development Sized
rds_config = {
  instance_class               = "db.t3.medium"
  allocated_storage           = 50
  max_allocated_storage      = 100
  multi_az                   = false
  backup_retention_period    = 7
  performance_insights_enabled = true
  deletion_protection        = false
  engine_version            = "15.3"
  family                    = "postgres15"
}

# Redis Configuration - Development Sized
redis_config = {
  node_type                  = "cache.t3.small"
  num_cache_nodes           = 1
  parameter_group_family    = "redis7"
  automatic_failover_enabled = false
  multi_az_enabled         = false
  engine_version           = "7.0"
  port                     = 6379
}

# MongoDB Configuration - Development Sized
mongodb_config = {
  instance_class             = "db.t3.medium"
  replica_count             = 1
  backup_retention_period   = 7
  preferred_backup_window   = "03:00-04:00"
  engine_version           = "5.0"
  deletion_protection      = false
  auto_minor_version_upgrade = true
}

# Resource Tags
tags = {
  Project     = "SpatialTag"
  ManagedBy   = "Terraform"
  Environment = "dev"
  Owner       = "Platform-Team"
  CostCenter  = "Development"
}

# Monitoring Configuration - Development Appropriate
monitoring_config = {
  retention_in_days        = 14
  enable_detailed_monitoring = false
  metrics_granularity     = "5Minute"
}