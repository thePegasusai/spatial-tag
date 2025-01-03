# Provider Configuration
# AWS Provider v5.0
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
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Local Variables
locals {
  name_prefix = "${var.environment}-spatial-tag"
  common_tags = {
    Environment  = var.environment
    Project      = "SpatialTag"
    ManagedBy    = "Terraform"
    Region       = var.aws_region
    LastUpdated  = timestamp()
  }
}

# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  environment         = var.environment
  name_prefix        = local.name_prefix
  vpc_config         = var.vpc_config
  tags               = local.common_tags
}

# EKS Module
module "eks" {
  source = "./modules/eks"
  
  environment         = var.environment
  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  private_subnets    = module.vpc.private_subnets
  eks_config         = var.eks_config
  tags               = local.common_tags

  depends_on = [module.vpc]
}

# Database Module
module "databases" {
  source = "./modules/databases"
  
  environment         = var.environment
  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  private_subnets    = module.vpc.private_subnets
  rds_config         = var.rds_config
  redis_config       = var.redis_config
  mongodb_config     = var.mongodb_config
  tags               = local.common_tags

  depends_on = [module.vpc]
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name
    ]
  }
}

# Helm Provider Configuration
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name
      ]
    }
  }
}

# VPC Outputs
output "vpc_outputs" {
  description = "VPC infrastructure details"
  value = {
    vpc_id          = module.vpc.vpc_id
    private_subnets = module.vpc.private_subnets
    public_subnets  = module.vpc.public_subnets
  }
}

# EKS Outputs
output "eks_outputs" {
  description = "EKS cluster details"
  value = {
    cluster_endpoint         = module.eks.cluster_endpoint
    cluster_name            = module.eks.cluster_name
    cluster_security_group_id = module.eks.cluster_security_group_id
  }
}

# Database Outputs
output "database_outputs" {
  description = "Database endpoints"
  value = {
    rds_endpoint     = module.databases.rds_endpoint
    redis_endpoint   = module.databases.redis_endpoint
    mongodb_endpoint = module.databases.mongodb_endpoint
  }
  sensitive = true
}