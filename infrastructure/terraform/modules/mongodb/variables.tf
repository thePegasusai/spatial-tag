# MongoDB Atlas project configuration
variable "project_id" {
  type        = string
  description = "MongoDB Atlas project identifier"
}

variable "cluster_name" {
  type        = string
  description = "Name of the MongoDB Atlas cluster"
}

variable "environment" {
  type        = string
  description = "Deployment environment (development, staging, production)"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# Instance and cluster configuration
variable "instance_type" {
  type        = string
  description = "MongoDB Atlas instance size (e.g., M30, M40, M50, etc.)"
}

variable "shard_count" {
  type        = number
  description = "Number of shards for the MongoDB cluster"
  default     = 1
}

variable "geospatial_index_config" {
  type        = map(string)
  description = "Configuration for geospatial indexing in MongoDB"
  default = {
    "2dsphere_version" = "3"
    "index_precision"  = "fine"
  }
}

# Backup configuration
variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain MongoDB backups"
  default     = 7
}

# Authentication
variable "atlas_public_key" {
  type        = string
  description = "MongoDB Atlas API public key for authentication"
  sensitive   = true
}

variable "atlas_private_key" {
  type        = string
  description = "MongoDB Atlas API private key for authentication"
  sensitive   = true
}

# Network configuration
variable "vpc_id" {
  type        = string
  description = "AWS VPC ID for MongoDB Atlas network peering"
}

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block of the VPC for network peering"
}

variable "atlas_cidr_block" {
  type        = string
  description = "CIDR block for MongoDB Atlas network container"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID for network peering configuration"
}