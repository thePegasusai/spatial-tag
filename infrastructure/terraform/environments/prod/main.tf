# Production Environment Terraform Configuration
# AWS Provider v5.0
# Kubernetes Provider v2.23
# Helm Provider v2.11

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
    bucket         = "spatial-tag-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-prod"
    kms_key_id     = "alias/terraform-state-key-prod"
  }
}

# Local Variables
locals {
  environment = "prod"
  aws_region = "us-east-1"
  backup_region = "us-west-2"
  common_tags = {
    Environment = "production"
    Project = "spatial-tag"
    ManagedBy = "terraform"
    ComplianceLevel = "high"
    DataClassification = "sensitive"
  }
}

# Fetch Available Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# AWS Provider Configuration
provider "aws" {
  region = local.aws_region
  
  default_tags {
    tags = local.common_tags
  }
}

# Backup Region Provider
provider "aws" {
  alias  = "backup"
  region = local.backup_region
  
  default_tags {
    tags = local.common_tags
  }
}

# Root Module Implementation
module "root" {
  source = "../../"

  environment = local.environment
  aws_region = local.aws_region
  backup_region = local.backup_region

  # VPC Configuration
  vpc_config = {
    cidr_block = "10.0.0.0/16"
    availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
    private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
    enable_nat_gateway = true
    single_nat_gateway = false
    enable_vpn_gateway = true
  }

  # EKS Configuration
  eks_config = {
    cluster_version = "1.27"
    node_groups = {
      general = {
        instance_types = ["m5.xlarge"]
        min_size = 3
        max_size = 10
        desired_size = 5
        disk_size = 100
        capacity_type = "ON_DEMAND"
      }
      spatial = {
        instance_types = ["c5.2xlarge"]
        min_size = 2
        max_size = 8
        desired_size = 4
        disk_size = 200
        capacity_type = "ON_DEMAND"
      }
    }
    cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    cluster_endpoint_private_access = true
    cluster_endpoint_public_access = true
  }

  # Security Configuration
  security_config = {
    enable_waf = true
    enable_shield = true
    enable_guardduty = true
    enable_security_hub = true
    enable_config = true
    enable_cloudtrail = true
    ssl_policy = "ELBSecurityPolicy-TLS-1-2-2017-01"
    backup_retention = 30
  }

  # Monitoring Configuration
  monitoring_config = {
    retention_in_days = 90
    enable_detailed_monitoring = true
    metrics_granularity = "1Minute"
    enable_prometheus = true
    enable_grafana = true
    enable_alertmanager = true
    enable_cloudwatch_logs = true
  }

  # Compliance Configuration
  compliance_config = {
    enable_hipaa_compliance = true
    enable_pci_compliance = true
    enable_sox_compliance = true
    enable_gdpr_compliance = true
  }

  # Disaster Recovery Configuration
  dr_config = {
    enable_cross_region_backup = true
    backup_region = local.backup_region
    rpo_hours = 1
    rto_hours = 4
    enable_pilot_light = true
  }

  tags = local.common_tags
}

# Infrastructure Outputs
output "infrastructure_endpoints" {
  description = "Production infrastructure endpoints"
  value = {
    vpc_id = module.root.vpc_outputs.vpc_id
    eks_endpoint = module.root.eks_outputs.cluster_endpoint
    database_endpoints = {
      rds = module.root.database_outputs.rds_endpoint
      redis = module.root.database_outputs.redis_endpoint
      mongodb = module.root.database_outputs.mongodb_endpoint
    }
    monitoring_endpoints = {
      prometheus = module.root.monitoring_outputs.prometheus_endpoint
      grafana = module.root.monitoring_outputs.grafana_endpoint
      alertmanager = module.root.monitoring_outputs.alertmanager_endpoint
    }
  }
  sensitive = true
}