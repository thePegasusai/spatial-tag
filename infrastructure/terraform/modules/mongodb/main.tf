# Provider configuration
# AWS Provider version ~> 5.0
provider "aws" {
  region = var.aws_region
}

# MongoDB Atlas Provider version ~> 1.0
provider "mongodbatlas" {
  public_key  = var.atlas_public_key
  private_key = var.atlas_private_key
}

# MongoDB Atlas Cluster Configuration
resource "mongodbatlas_cluster" "spatial_tag_cluster" {
  project_id   = var.project_id
  name         = "${var.cluster_name}-${var.environment}"
  cluster_type = "SHARDED"
  
  # MongoDB version 6.0 as specified in technical requirements
  mongo_db_major_version = "6.0"

  # Cloud provider settings
  provider_name               = "AWS"
  provider_region_name        = var.aws_region
  provider_instance_size_name = var.instance_type

  # Sharding configuration for tag content and spatial data
  num_shards = var.shard_count

  # Replication configuration for high availability
  replication_specs {
    num_shards = var.shard_count
    regions_config {
      region_name     = var.aws_region
      priority        = 7
      read_only_nodes = 0
      analytics_nodes = 1
    }
  }

  # Backup configuration
  backup_enabled     = true
  pit_enabled        = true
  retention_in_days  = var.backup_retention_days

  # Auto-scaling configuration
  auto_scaling_disk_gb_enabled = true
  auto_scaling_compute_enabled = true

  # Advanced configuration
  advanced_configuration {
    javascript_enabled           = false
    minimum_enabled_tls_protocol = "TLS1_2"
    no_table_scan               = false
    oplog_size_mb              = 51200  # 50GB oplog for high write workloads
    
    # Index configuration for geospatial queries
    default_read_concern        = "majority"
    default_write_concern      = "majority"
  }

  # Tags for resource management
  tags {
    environment = var.environment
    project     = "spatial-tag"
  }
}

# Network Container for VPC Peering
resource "mongodbatlas_network_container" "container" {
  project_id       = var.project_id
  atlas_cidr_block = var.atlas_cidr_block
  provider_name    = "AWS"
  region_name      = var.aws_region
}

# VPC Peering Connection
resource "mongodbatlas_network_peering" "vpc_peering" {
  project_id            = var.project_id
  container_id         = mongodbatlas_network_container.container.container_id
  vpc_id               = var.vpc_id
  aws_account_id       = var.aws_account_id
  route_table_cidr_block = var.vpc_cidr_block
  region_name          = var.aws_region
}

# AWS VPC Peering Connection Accepter
resource "aws_vpc_peering_connection_accepter" "mongodb_peer" {
  vpc_peering_connection_id = mongodbatlas_network_peering.vpc_peering.connection_id
  auto_accept              = true

  tags = {
    Name        = "MongoDB Atlas VPC Peering"
    Environment = var.environment
    Project     = "spatial-tag"
  }
}

# Security Group for MongoDB Access
resource "aws_security_group" "mongodb_access" {
  name_prefix = "mongodb-atlas-access-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [var.atlas_cidr_block]
    description = "MongoDB Atlas Access"
  }

  tags = {
    Name        = "MongoDB Atlas Access"
    Environment = var.environment
    Project     = "spatial-tag"
  }
}

# Route Table Entry for MongoDB Atlas
resource "aws_route" "mongodb_atlas" {
  route_table_id         = data.aws_vpc.selected.main_route_table_id
  destination_cidr_block = var.atlas_cidr_block
  vpc_peering_connection_id = mongodbatlas_network_peering.vpc_peering.connection_id
}

# Data source for VPC information
data "aws_vpc" "selected" {
  id = var.vpc_id
}