# Database Connection Information
output "db_endpoint" {
  description = "The connection endpoint for the primary RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_id" {
  description = "The identifier of the primary RDS instance"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "The ARN of the primary RDS instance"
  value       = aws_db_instance.main.arn
}

# Network Configuration
output "db_subnet_group_id" {
  description = "The ID of the DB subnet group"
  value       = aws_db_subnet_group.main.id
}

output "db_security_group_id" {
  description = "The ID of the security group associated with the RDS instance"
  value       = aws_db_security_group.rds.id
}

# Read Replica Information
output "db_replica_endpoints" {
  description = "The connection endpoints of the read replicas"
  value       = aws_db_instance.replica[*].endpoint
}

# Monitoring Information
output "enhanced_monitoring_iam_role_arn" {
  description = "The ARN of the IAM role used for enhanced monitoring"
  value       = aws_iam_role.rds_enhanced_monitoring.arn
}

# Parameter Group Information
output "parameter_group_id" {
  description = "The ID of the DB parameter group"
  value       = aws_db_parameter_group.main.id
}

# Secret Information
output "master_password_secret_arn" {
  description = "The ARN of the secret storing the master password"
  value       = aws_secretsmanager_secret.db_password.arn
}

# High Availability Information
output "multi_az_enabled" {
  description = "Whether the RDS instance is configured for high availability"
  value       = aws_db_instance.main.multi_az
}

# Storage Information
output "allocated_storage" {
  description = "The amount of allocated storage in gibibytes"
  value       = aws_db_instance.main.allocated_storage
}

output "storage_encrypted" {
  description = "Whether the storage is encrypted"
  value       = aws_db_instance.main.storage_encrypted
}