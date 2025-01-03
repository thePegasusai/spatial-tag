# Terraform Configuration Block
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  backend "s3" {
    bucket         = "spatial-tag-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Local Variables
locals {
  environment = "staging"
  common_tags = {
    Environment        = "staging"
    Project           = "SpatialTag"
    ManagedBy         = "Terraform"
    CostCenter        = "PreProduction"
    DataClassification = "Confidential"
  }
}

# AWS Provider Configuration
provider "aws" {
  region = "us-east-1"
  
  default_tags {
    tags = local.common_tags
  }
}

# Root Module Configuration
module "root_module" {
  source = "../../"

  environment = local.environment
  aws_region  = "us-east-1"

  vpc_config = {
    cidr_block           = "10.1.0.0/16"  # Staging VPC CIDR
    availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
    private_subnets     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
    public_subnets      = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
    enable_nat_gateway  = true
    single_nat_gateway  = false  # Multi-AZ NAT for high availability
    enable_vpn_gateway  = false
  }

  eks_config = {
    cluster_version = "1.27"
    node_groups = {
      general = {
        instance_types  = ["t3.xlarge"]  # Larger instances for staging
        min_size       = 3
        max_size       = 6
        desired_size   = 3
        disk_size      = 100
        capacity_type  = "ON_DEMAND"
      }
    }
    cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    cluster_endpoint_private_access = true
    cluster_endpoint_public_access  = true
  }

  rds_config = {
    instance_class               = "db.t3.xlarge"
    allocated_storage           = 200
    max_allocated_storage      = 1000
    multi_az                   = true
    backup_retention_period    = 7
    performance_insights_enabled = true
    deletion_protection        = true
    engine_version            = "15.3"
    family                    = "postgres15"
  }

  redis_config = {
    node_type                  = "cache.t3.medium"
    num_cache_nodes           = 3
    parameter_group_family    = "redis7"
    automatic_failover_enabled = true
    multi_az_enabled         = true
    engine_version           = "7.0"
    port                     = 6379
  }

  mongodb_config = {
    instance_class             = "db.r5.xlarge"
    replica_count             = 3
    backup_retention_period   = 7
    preferred_backup_window   = "03:00-04:00"
    engine_version           = "5.0"
    deletion_protection      = true
    auto_minor_version_upgrade = true
  }

  monitoring_config = {
    retention_in_days        = 30
    enable_detailed_monitoring = true
    metrics_granularity     = "1Minute"
  }

  tags = local.common_tags
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = module.root_module.eks_outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(module.root_module.eks_outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.root_module.eks_outputs.cluster_name
    ]
  }
}

# Helm Provider Configuration
provider "helm" {
  kubernetes {
    host                   = module.root_module.eks_outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(module.root_module.eks_outputs.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.root_module.eks_outputs.cluster_name
      ]
    }
  }
}

# Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.root_module.vpc_outputs.vpc_id
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS cluster"
  value       = module.root_module.eks_outputs.cluster_endpoint
}

output "database_endpoints" {
  description = "Database endpoints for the staging environment"
  value = {
    rds     = module.root_module.database_outputs.rds_endpoint
    redis   = module.root_module.database_outputs.redis_endpoint
    mongodb = module.root_module.database_outputs.mongodb_endpoint
  }
  sensitive = true
}