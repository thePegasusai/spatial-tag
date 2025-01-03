# Tag Service

A high-performance, scalable microservice for managing digital spatial tags in the Spatial Tag platform. This service handles the creation, retrieval, and lifecycle management of location-anchored digital markers with real-time spatial queries and optimized tag density management.

## Features

- Real-time spatial tag management with LiDAR integration
- Location-based tag discovery with configurable visibility radius
- Efficient geospatial indexing and querying
- Tag lifecycle management with automatic expiration
- Redis-based caching for high-performance queries
- Comprehensive monitoring and observability
- Security-first design with robust access controls

## Architecture

### Core Components

- **Tag Service**: Go-based gRPC service (v1.1.0)
- **MongoDB**: Primary data store with geospatial indexing (v1.11.0)
- **Redis**: Caching layer for high-performance queries (v8.11.5)
- **Prometheus**: Metrics collection and monitoring (v1.16.0)

### Data Model

```go
type Tag struct {
    ID               primitive.ObjectID     `bson:"_id,omitempty" json:"id"`
    CreatorID        string                `bson:"creator_id" json:"creator_id"`
    Location         Location              `bson:"location" json:"location"`
    Content          string                `bson:"content" json:"content"`
    MediaURLs        []string              `bson:"media_urls" json:"media_urls"`
    Category         string                `bson:"category" json:"category"`
    CreatedAt        time.Time             `bson:"created_at" json:"created_at"`
    ExpiresAt        time.Time             `bson:"expires_at" json:"expires_at"`
    VisibilityRadius float64               `bson:"visibility_radius" json:"visibility_radius"`
    Visibility       int                   `bson:"visibility" json:"visibility"`
    Status           int                   `bson:"status" json:"status"`
    InteractionCount int                   `bson:"interaction_count" json:"interaction_count"`
    Metadata         map[string]interface{} `bson:"metadata" json:"metadata"`
}
```

## Setup

### Prerequisites

- Go 1.21+
- MongoDB 6.0+
- Redis 7.0+
- Docker & Docker Compose
- Kubernetes (for production deployment)

### Environment Variables

```env
# Service Configuration
TAG_SERVICE_ENV=development
TAG_SERVICE_VERSION=1.0.0

# MongoDB Configuration
TAG_SERVICE_MONGO_URI=mongodb://localhost:27017
TAG_SERVICE_MONGO_DB=spatial_tag
TAG_SERVICE_MONGO_COLLECTION=tags
TAG_SERVICE_MONGO_TIMEOUT=10s
TAG_SERVICE_MONGO_MAX_POOL_SIZE=100

# gRPC Configuration
TAG_SERVICE_GRPC_HOST=0.0.0.0
TAG_SERVICE_GRPC_PORT=50051
TAG_SERVICE_GRPC_TIMEOUT=30s
TAG_SERVICE_GRPC_ENABLE_TLS=true

# Tag Configuration
TAG_SERVICE_TAG_DEFAULT_VISIBILITY_RADIUS=50.0
TAG_SERVICE_TAG_DEFAULT_EXPIRATION=24h
TAG_SERVICE_TAG_CLEANUP_INTERVAL=1h
TAG_SERVICE_TAG_MAX_PER_USER=100

# Security Configuration
TAG_SERVICE_SECURITY_ENABLE_AUDIT_LOG=true
TAG_SERVICE_SECURITY_TOKEN_EXPIRATION=1h
TAG_SERVICE_SECURITY_MAX_FAILED_ATTEMPTS=5
```

### Installation

1. Clone the repository:
```bash
git clone https://github.com/spatial-tag/tag-service.git
cd tag-service
```

2. Install dependencies:
```bash
go mod download
```

3. Build the service:
```bash
make build
```

4. Run tests:
```bash
make test
```

## API

### gRPC Service Definition

```protobuf
service TagService {
    rpc CreateTag(CreateTagRequest) returns (Tag);
    rpc GetNearbyTags(GetNearbyTagsRequest) returns (GetNearbyTagsResponse);
    rpc UpdateTag(UpdateTagRequest) returns (Tag);
    rpc DeleteTag(DeleteTagRequest) returns (google.protobuf.Empty);
    rpc BatchCreateTags(BatchCreateTagsRequest) returns (BatchCreateTagsResponse);
}
```

### Error Handling

| Error Code | Description |
|------------|-------------|
| INVALID_ARGUMENT | Invalid tag data or parameters |
| NOT_FOUND | Tag not found |
| PERMISSION_DENIED | Insufficient permissions |
| RESOURCE_EXHAUSTED | Rate limit exceeded |
| INTERNAL | Internal server error |

## Security

### Authentication & Authorization

- JWT-based authentication
- Role-based access control (RBAC)
- Rate limiting per user/IP
- Request validation and sanitization

### Data Protection

- TLS 1.3 for all communications
- Data encryption at rest
- PII data handling compliance
- Audit logging for sensitive operations

## Monitoring

### Metrics

- Tag operation latency
- Cache hit/miss rates
- Query performance
- Error rates
- Resource utilization

### Prometheus Metrics

```go
tagOperationDuration = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
        Name: "tag_service_operation_duration_seconds",
        Help: "Duration of tag service operations",
        Buckets: prometheus.ExponentialBuckets(0.01, 2, 10),
    },
    []string{"operation"},
)

tagOperationCounter = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "tag_service_operations_total",
        Help: "Total number of tag operations",
    },
    []string{"operation", "status"},
)
```

## Performance

### Optimization Strategies

- Geospatial indexing for efficient queries
- Redis caching for hot data
- Connection pooling
- Batch operations support
- Request pipelining

### Caching

- Tag data: 5 minutes TTL
- Nearby queries: 30 seconds TTL
- User data: 1 hour TTL
- Configurable per environment

## Development

### Code Style

- Follow Go best practices
- Use gofmt for formatting
- Implement comprehensive error handling
- Add unit tests for new features
- Document public APIs

### Testing

```bash
# Run unit tests
make test

# Run integration tests
make test-integration

# Run benchmarks
make bench
```

## Operations

### Deployment

```bash
# Build Docker image
docker build -t tag-service:latest .

# Deploy to Kubernetes
kubectl apply -f k8s/
```

### Health Checks

- Readiness probe: `/health/ready`
- Liveness probe: `/health/live`
- Startup probe: `/health/startup`

### Backup & Recovery

- Automated MongoDB backups
- Point-in-time recovery
- Disaster recovery procedures
- Data retention policies

## License

Copyright © 2023 Spatial Tag Platform. All rights reserved.