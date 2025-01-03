# Environment Identifier
environment = "staging"

# AWS Region Configuration
aws_region = "us-east-1"

# VPC Configuration
vpc_config = {
  cidr_block           = "10.1.0.0/16"  # Staging VPC CIDR range
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets      = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = false  # Multi-AZ NAT for staging
  enable_vpn_gateway  = false
}

# EKS Configuration
eks_config = {
  cluster_version = "1.27"
  node_groups = {
    general = {
      instance_types  = ["t3.xlarge"]  # Larger instances for staging workloads
      min_size       = 3
      max_size       = 6
      desired_size   = 3
      disk_size      = 100
      capacity_type  = "ON_DEMAND"
    }
    spatial = {  # Dedicated node group for spatial processing
      instance_types  = ["c6i.2xlarge"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      disk_size      = 150
      capacity_type  = "ON_DEMAND"
    }
  }
  cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
}

# RDS Configuration
rds_config = {
  instance_class               = "db.r5.xlarge"
  allocated_storage           = 200
  max_allocated_storage       = 1000
  multi_az                    = true  # Enable Multi-AZ for staging
  backup_retention_period     = 7
  performance_insights_enabled = true
  deletion_protection         = true
  engine_version             = "15.3"
  family                     = "postgres15"
}

# Redis Configuration
redis_config = {
  node_type                  = "cache.r5.large"
  num_cache_nodes           = 2
  parameter_group_family    = "redis7"
  automatic_failover_enabled = true
  multi_az_enabled          = true
  engine_version            = "7.0"
  port                      = 6379
}

# MongoDB Configuration
mongodb_config = {
  instance_class             = "db.r5.xlarge"
  replica_count             = 3  # 3 replicas for high availability
  backup_retention_period   = 7
  preferred_backup_window   = "03:00-04:00"
  engine_version           = "5.0"
  deletion_protection      = true
  auto_minor_version_upgrade = true
}

# Resource Tags
tags = {
  Environment = "staging"
  Project     = "SpatialTag"
  ManagedBy   = "Terraform"
  Owner       = "Platform-Team"
  CostCenter  = "STG-001"
}

# Monitoring Configuration
monitoring_config = {
  retention_in_days         = 30
  enable_detailed_monitoring = true
  metrics_granularity      = "1Minute"
}