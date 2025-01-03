# AWS Provider version constraint
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Generate secure master password
resource "random_password" "master_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store master password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "spatial-tag/${var.identifier}/master-password"
  tags = merge(var.tags, {
    Name = "spatial-tag-${var.identifier}-master-password"
  })
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.master_password.result
}

# DB Subnet Group for Multi-AZ deployment
resource "aws_db_subnet_group" "main" {
  name        = "spatial-tag-${var.identifier}"
  description = "Subnet group for Spatial Tag RDS PostgreSQL"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "spatial-tag-${var.identifier}-subnet-group"
  })
}

# Security Group for RDS instance
resource "aws_security_group" "rds" {
  name        = "spatial-tag-${var.identifier}-rds"
  description = "Security group for Spatial Tag RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL access from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  tags = merge(var.tags, {
    Name = "spatial-tag-${var.identifier}-sg"
  })
}

# Custom Parameter Group for PostgreSQL optimization
resource "aws_db_parameter_group" "main" {
  name        = "spatial-tag-${var.identifier}"
  family      = var.parameter_group_family
  description = "Custom parameter group for Spatial Tag PostgreSQL"

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  parameter {
    name  = "max_connections"
    value = "1000"
  }

  parameter {
    name  = "work_mem"
    value = "4096"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "1048576"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }

  tags = merge(var.tags, {
    Name = "spatial-tag-${var.identifier}-pg"
  })
}

# Enhanced Monitoring IAM Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "spatial-tag-${var.identifier}-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"]
}

# Primary RDS Instance
resource "aws_db_instance" "main" {
  identifier = var.identifier
  engine     = "postgres"
  engine_version = var.engine_version

  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = var.storage_encrypted
  kms_key_id           = var.kms_key_id

  db_name  = var.database_name
  username = var.master_username
  password = random_password.master_password.result
  port     = 5432

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_retention_period = 7
  monitoring_interval            = var.monitoring_interval
  monitoring_role_arn           = aws_iam_role.rds_enhanced_monitoring.arn

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot      = false
  final_snapshot_identifier = "${var.identifier}-final-snapshot"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(var.tags, {
    Name = "spatial-tag-${var.identifier}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Read Replica for enhanced read performance
resource "aws_db_instance" "replica" {
  count = var.multi_az ? 1 : 0

  identifier = "${var.identifier}-replica"
  instance_class = var.instance_class
  
  replicate_source_db = aws_db_instance.main.id
  
  multi_az               = false
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_retention_period = 7
  monitoring_interval            = var.monitoring_interval
  monitoring_role_arn           = aws_iam_role.rds_enhanced_monitoring.arn

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot     = true
  
  tags = merge(var.tags, {
    Name = "spatial-tag-${var.identifier}-replica"
  })
}

# Data source for VPC CIDR
data "aws_vpc" "selected" {
  id = var.vpc_id
}