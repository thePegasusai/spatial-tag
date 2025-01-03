# Terraform ~> 1.6 required for variable validation features

variable "environment" {
  type        = string
  description = "Deployment environment identifier (dev/staging/prod)"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC network"
  
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block (e.g., 10.0.0.0/16)"
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of AWS availability zones for multi-AZ deployment"
  
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones must be specified for high availability"
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets (one per AZ)"
  
  validation {
    condition     = alltrue([
      for cidr in var.public_subnet_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All public subnet CIDRs must be valid IPv4 CIDR blocks"
  }
  
  validation {
    condition     = length(var.public_subnet_cidrs) > 0
    error_message = "At least one public subnet CIDR must be specified"
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets (one per AZ)"
  
  validation {
    condition     = alltrue([
      for cidr in var.private_subnet_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All private subnet CIDRs must be valid IPv4 CIDR blocks"
  }
  
  validation {
    condition     = length(var.private_subnet_cidrs) > 0
    error_message = "At least one private subnet CIDR must be specified"
  }
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for database subnets (one per AZ)"
  
  validation {
    condition     = alltrue([
      for cidr in var.database_subnet_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All database subnet CIDRs must be valid IPv4 CIDR blocks"
  }
  
  validation {
    condition     = length(var.database_subnet_cidrs) > 0
    error_message = "At least one database subnet CIDR must be specified"
  }
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway for private subnet internet access"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Resource tags to be applied to all VPC resources"
  default     = {}
}