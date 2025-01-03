# Terraform variables definition file for EKS module
# Version: ~> 1.6

variable "cluster_name" {
  description = "Name of the EKS cluster for the Spatial Tag platform"
  type        = string

  validation {
    condition     = length(var.cluster_name) <= 100
    error_message = "Cluster name must be 100 characters or less"
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (must be 1.27 or higher)"
  type        = string
  default     = "1.27"

  validation {
    condition     = can(regex("^1\\.(2[7-9]|[3-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be 1.27 or higher"
  }
}

variable "vpc_id" {
  description = "ID of the VPC where EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS node groups (minimum 2 for high availability)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for high availability"
  }
}

variable "node_groups" {
  description = "Configuration map for EKS node groups"
  type = map(object({
    instance_types = list(string)
    desired_size   = number
    min_size      = number
    max_size      = number
    disk_size     = number
    capacity_type = string
  }))

  validation {
    condition     = alltrue([for ng in var.node_groups : ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size])
    error_message = "Node group sizes must satisfy: min_size <= desired_size <= max_size"
  }
}

variable "tags" {
  description = "Resource tags for EKS cluster and node groups"
  type        = map(string)
  default = {
    Environment = "production"
    Application = "spatial-tag"
    ManagedBy   = "terraform"
  }
}