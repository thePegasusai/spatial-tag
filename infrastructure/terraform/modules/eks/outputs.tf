# Output definitions for the EKS module
# Version: ~> 1.6
# Purpose: Expose essential EKS cluster information for other modules and services
# Security: Sensitive information is marked appropriately to prevent exposure

output "cluster_id" {
  description = <<-EOT
    The EKS cluster identifier.
    Used for resource referencing and integration with other AWS services.
    Format: <cluster-name>-<uuid>
  EOT
  value       = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  description = <<-EOT
    The endpoint URL for the EKS cluster API server.
    Used for:
    - Service communication
    - kubectl access configuration
    - Authentication setup
    Note: Endpoint is private by default as per security configuration
  EOT
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = <<-EOT
    Security group ID attached to the EKS cluster.
    Used for:
    - Network access control
    - Firewall rules configuration
    - Service mesh setup
    - Cross-service communication
  EOT
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = <<-EOT
    Base64 encoded certificate data required for cluster authentication.
    Used for:
    - Secure API server communication
    - Client-side kubectl configuration
    - Service account setup
    WARNING: This is sensitive information and should be handled securely
  EOT
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "node_groups" {
  description = <<-EOT
    Map of all EKS node groups and their configurations.
    Contains information about:
    - Instance types
    - Scaling configurations
    - Capacity type
    - Subnet placement
    Used for:
    - Cluster scaling management
    - Resource monitoring
    - Capacity planning
  EOT
  value = {
    for ng_key, ng in aws_eks_node_group.main : ng_key => {
      node_group_name = ng.node_group_name
      status         = ng.status
      capacity_type  = ng.capacity_type
      scaling_config = ng.scaling_config
      subnet_ids     = ng.subnet_ids
      instance_types = ng.instance_types
      disk_size      = ng.disk_size
    }
  }
}

output "cluster_name" {
  description = <<-EOT
    The name of the EKS cluster.
    Used for:
    - Resource tagging
    - Service discovery
    - Monitoring configuration
    - Log aggregation
  EOT
  value = aws_eks_cluster.main.name
}

output "cluster_version" {
  description = <<-EOT
    The Kubernetes version running on the EKS cluster.
    Used for:
    - Version compatibility checks
    - Upgrade planning
    - Plugin configuration
  EOT
  value = aws_eks_cluster.main.version
}

output "cluster_arn" {
  description = <<-EOT
    The ARN (Amazon Resource Name) of the EKS cluster.
    Used for:
    - IAM policy configuration
    - Cross-account access
    - Resource policies
  EOT
  value = aws_eks_cluster.main.arn
}

output "cluster_platform_version" {
  description = <<-EOT
    The platform version of the EKS cluster.
    Used for:
    - Platform feature compatibility
    - Security patch verification
    - Compliance reporting
  EOT
  value = aws_eks_cluster.main.platform_version
}