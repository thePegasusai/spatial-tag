# MongoDB Atlas cluster identifier output
output "cluster_id" {
  value       = mongodbatlas_cluster.spatial_tag_cluster.cluster_id
  description = "The unique identifier of the MongoDB Atlas cluster for tag content and metadata storage"
}

# MongoDB connection string output (sensitive)
output "connection_string" {
  value       = mongodbatlas_cluster.spatial_tag_cluster.connection_strings[0].standard
  description = "MongoDB Atlas connection string for application configuration with sharded cluster support"
  sensitive   = true
}

# VPC peering connection ID output
output "peering_connection_id" {
  value       = mongodbatlas_network_peering.vpc_peering.connection_id
  description = "The ID of the VPC peering connection between AWS and MongoDB Atlas"
}

# Security group ID output
output "security_group_id" {
  value       = aws_security_group.mongodb_access.id
  description = "ID of the security group created for MongoDB Atlas access"
}

# MongoDB Atlas cluster state output
output "cluster_state" {
  value       = mongodbatlas_cluster.spatial_tag_cluster.state_name
  description = "Current state of the MongoDB Atlas cluster"
}

# MongoDB version output
output "mongodb_version" {
  value       = mongodbatlas_cluster.spatial_tag_cluster.mongo_db_major_version
  description = "MongoDB version running on the Atlas cluster"
}

# Cluster connection details output (sensitive)
output "cluster_connection_details" {
  value = {
    standard_srv    = mongodbatlas_cluster.spatial_tag_cluster.connection_strings[0].standard_srv
    private_srv     = mongodbatlas_cluster.spatial_tag_cluster.connection_strings[0].private_srv
    private_endoint = mongodbatlas_cluster.spatial_tag_cluster.connection_strings[0].private
  }
  description = "Detailed connection information for the MongoDB Atlas cluster"
  sensitive   = true
}

# Backup configuration output
output "backup_enabled" {
  value       = mongodbatlas_cluster.spatial_tag_cluster.backup_enabled
  description = "Indicates if backup is enabled for the MongoDB Atlas cluster"
}

# Cluster endpoint output
output "cluster_endpoint" {
  value       = mongodbatlas_cluster.spatial_tag_cluster.mongo_uri
  description = "MongoDB URI for connecting to the Atlas cluster"
  sensitive   = true
}