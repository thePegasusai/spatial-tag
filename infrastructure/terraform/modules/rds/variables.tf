# RDS PostgreSQL Module Variables
# Terraform Version: ~> 1.6

# Basic Instance Configuration
variable "identifier" {
  description = "Unique identifier for the RDS instance"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.3"
}

variable "instance_class" {
  description = "RDS instance type for compute and memory resources"
  type        = string
  default     = "db.r6g.xlarge"
}

# Storage Configuration
variable "allocated_storage" {
  description = "Size of the database storage in gigabytes"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Maximum storage limit for autoscaling"
  type        = number
  default     = 1000
}

# Database Configuration
variable "database_name" {
  description = "Name of the initial database to be created"
  type        = string
}

variable "master_username" {
  description = "Master username for database administration"
  type        = string
  sensitive   = true
}

# Network Configuration
variable "vpc_id" {
  description = "ID of the VPC where RDS will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for RDS multi-AZ deployment"
  type        = list(string)
}

# High Availability Configuration
variable "multi_az" {
  description = "Enable/disable multi-AZ deployment for high availability"
  type        = bool
  default     = true
}

# Backup Configuration
variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

# Security Configuration
variable "storage_encrypted" {
  description = "Enable/disable storage encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for storage encryption"
  type        = string
  default     = null
}

# Performance and Monitoring Configuration
variable "performance_insights_enabled" {
  description = "Enable/disable Performance Insights"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be 0, 1, 5, 10, 15, 30, or 60 seconds."
  }
}

# Parameter Group Configuration
variable "parameter_group_family" {
  description = "Database parameter group family"
  type        = string
  default     = "postgres15"
}

# Resource Tagging
variable "tags" {
  description = "Resource tags to be applied to the RDS instance"
  type        = map(string)
  default     = {}
}