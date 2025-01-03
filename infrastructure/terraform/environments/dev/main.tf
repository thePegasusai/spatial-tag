# Provider configuration
# AWS provider version ~> 5.0
provider "aws" {
  region = local.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# Kubernetes provider version ~> 2.23
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Helm provider version ~> 2.11
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# Local variables
locals {
  environment  = "dev"
  aws_region   = "us-east-1"
  name_prefix  = "dev-spatial-tag"
  common_tags  = {
    Environment   = "dev"
    Project       = "SpatialTag"
    ManagedBy     = "Terraform"
    CostCenter    = "Development"
    AutoShutdown  = "true"
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = "10.0.0.0/16"

  azs               = ["us-east-1a", "us-east-1b"]
  private_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets    = ["10.0.101.0/24", "10.0.102.0/24"]
  database_subnets  = ["10.0.201.0/24", "10.0.202.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_vpn_gateway   = false

  tags = local.common_tags
}

# EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "${local.name_prefix}-eks"
  cluster_version = "1.27"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size      = 1
      max_size      = 3
      disk_size     = 50
    }
  }

  tags = local.common_tags
}

# RDS Module
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${local.name_prefix}-db"

  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  max_allocated_storage = 50

  vpc_security_group_ids = [module.vpc.default_security_group_id]
  subnet_ids             = module.vpc.database_subnets

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  tags = local.common_tags
}

# ElastiCache Module
module "elasticache" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "~> 3.0"

  cluster_id           = "${local.name_prefix}-redis"
  engine              = "redis"
  node_type           = "cache.t3.micro"
  num_cache_nodes     = 1
  parameter_group_family = "redis7"
  port                = 6379

  subnet_ids          = module.vpc.database_subnets
  security_group_ids  = [module.vpc.default_security_group_id]
  maintenance_window  = "tue:05:00-tue:06:00"

  tags = local.common_tags
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "database_endpoints" {
  description = "Database endpoints"
  value = {
    rds_endpoint   = module.rds.db_instance_endpoint
    redis_endpoint = module.elasticache.redis_endpoint
  }
}