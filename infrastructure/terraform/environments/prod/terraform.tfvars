# Environment Configuration
environment = "prod"
aws_region  = "us-east-1"

# VPC Configuration
vpc_config = {
  cidr_block          = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets      = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = false
  enable_vpn_gateway  = false
}

# EKS Configuration
eks_config = {
  cluster_version = "1.27"
  node_groups = {
    general = {
      instance_types  = ["m5.2xlarge"]
      min_size       = 3
      max_size       = 10
      desired_size   = 5
      disk_size      = 100
      capacity_type  = "ON_DEMAND"
    }
    spatial = {
      instance_types  = ["c5.2xlarge"]
      min_size       = 2
      max_size       = 8
      desired_size   = 4
      disk_size      = 100
      capacity_type  = "ON_DEMAND"
    }
  }
  cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
}

# RDS Configuration
rds_config = {
  instance_class               = "db.r6g.2xlarge"
  allocated_storage           = 500
  max_allocated_storage      = 2000
  multi_az                   = true
  backup_retention_period    = 30
  performance_insights_enabled = true
  deletion_protection        = true
  engine_version            = "15.3"
  family                    = "postgres15"
}

# Redis Configuration
redis_config = {
  node_type                  = "cache.r6g.xlarge"
  num_cache_nodes           = 3
  parameter_group_family    = "redis7"
  automatic_failover_enabled = true
  multi_az_enabled         = true
  engine_version           = "7.0"
  port                     = 6379
}

# MongoDB Configuration
mongodb_config = {
  instance_class             = "db.r6g.2xlarge"
  replica_count             = 3
  backup_retention_period   = 30
  preferred_backup_window   = "03:00-04:00"
  engine_version           = "5.0"
  deletion_protection      = true
  auto_minor_version_upgrade = true
}

# Resource Tags
tags = {
  Project     = "SpatialTag"
  ManagedBy   = "Terraform"
  Environment = "prod"
  Owner       = "Platform-Team"
  CostCenter  = "PROD-001"
  Compliance  = "SOC2"
}

# Monitoring Configuration
monitoring_config = {
  retention_in_days        = 90
  enable_detailed_monitoring = true
  metrics_granularity     = "1Minute"
}