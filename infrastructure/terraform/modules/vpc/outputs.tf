# VPC Outputs
output "vpc_id" {
  description = "The ID of the created VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "List of public subnet IDs for external-facing resources"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs for internal resources"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "List of database subnet IDs for data layer resources"
  value       = aws_subnet.database[*].id
}

# Security Group Outputs
output "eks_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.eks.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS instances"
  value       = aws_security_group.rds.id
}

output "redis_security_group_id" {
  description = "Security group ID for Redis clusters"
  value       = aws_security_group.redis.id
}

output "mongodb_security_group_id" {
  description = "Security group ID for MongoDB clusters"
  value       = aws_security_group.mongodb.id
}