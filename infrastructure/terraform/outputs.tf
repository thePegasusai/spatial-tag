# Database outputs for application configuration
output "database_outputs" {
  description = "Database connection details for application configuration"
  value = {
    rds_endpoint         = aws_rds_cluster.main.endpoint
    rds_instance_id      = aws_rds_cluster.main.cluster_identifier
    rds_port            = aws_rds_cluster.main.port
    documentdb_endpoint = aws_docdb_cluster.main.endpoint
    documentdb_port     = aws_docdb_cluster.main.port
  }
  sensitive = true
}

# Kubernetes cluster information for application deployment
output "kubernetes_outputs" {
  description = "EKS cluster information for application deployment"
  value = {
    cluster_endpoint           = aws_eks_cluster.main.endpoint
    cluster_name              = aws_eks_cluster.main.name
    cluster_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    node_security_group_id    = aws_eks_cluster.main.vpc_config[0].security_group_ids[0]
    cluster_oidc_issuer_url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
  }
}

# Cache endpoints for Redis configuration
output "cache_outputs" {
  description = "Redis endpoints for caching and spatial data storage"
  value = {
    redis_primary_endpoint   = aws_elasticache_replication_group.main.primary_endpoint_address
    redis_reader_endpoint    = aws_elasticache_replication_group.main.reader_endpoint_address
    redis_port              = aws_elasticache_replication_group.main.port
    redis_security_group_id = aws_elasticache_replication_group.main.security_group_ids[0]
  }
  sensitive = true
}

# Storage information for S3 and CloudFront
output "storage_outputs" {
  description = "S3 bucket information for media storage and logging"
  value = {
    media_bucket_name         = aws_s3_bucket.media.id
    media_bucket_arn         = aws_s3_bucket.media.arn
    logs_bucket_name         = aws_s3_bucket.logs.id
    cloudfront_distribution_id = aws_cloudfront_distribution.main.id
  }
}

# Network configuration details
output "network_outputs" {
  description = "Networking details for service configuration"
  value = {
    vpc_id              = aws_vpc.main.id
    private_subnet_ids = aws_subnet.private[*].id
    public_subnet_ids  = aws_subnet.public[*].id
    load_balancer_dns  = aws_lb.main.dns_name
    route53_zone_id    = aws_route53_zone.main.zone_id
  }
}

# Monitoring and logging endpoints
output "monitoring_outputs" {
  description = "Monitoring and logging endpoint information"
  value = {
    prometheus_endpoint     = aws_prometheus_workspace.main.prometheus_endpoint
    grafana_endpoint       = aws_grafana_workspace.main.endpoint
    elasticsearch_endpoint = aws_elasticsearch_domain.main.endpoint
    cloudwatch_log_group   = aws_cloudwatch_log_group.main.name
  }
  sensitive = true
}