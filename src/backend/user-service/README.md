# User Service

A high-performance, secure microservice handling user management, authentication, and status tracking for the Spatial Tag platform.

## Overview

The User Service is a Node.js-based microservice that manages user profiles, authentication, and status tracking within the Spatial Tag ecosystem. Built with gRPC for high-performance communication, it provides robust user management capabilities while maintaining strict security standards.

## Features

- JWT-based authentication with refresh token support
- Tiered user classification (Elite/Rare status)
- Real-time location tracking and proximity detection
- Comprehensive user preference management
- High-performance gRPC API endpoints
- Containerized deployment with Docker
- Extensive security measures and monitoring

## Prerequisites

- Node.js >= 20.0.0
- Docker >= 24.0.0
- MongoDB
- Redis
- Protocol Buffers compiler

## Installation

1. Clone the repository
2. Install dependencies:
```bash
npm ci
```

3. Generate Protocol Buffer types:
```bash
npm run proto:gen
```

4. Build the service:
```bash
npm run build
```

## Configuration

Create a `.env` file with the following variables:

```env
# Server
NODE_ENV=production
PORT=50051
HOST=0.0.0.0

# Authentication
JWT_SECRET=your-secret-key
JWT_EXPIRY=1h
REFRESH_TOKEN_EXPIRY=7d

# Databases
MONGODB_URI=mongodb://localhost:27017/spatial-tag
REDIS_URL=redis://localhost:6379

# Rate Limiting
RATE_LIMIT_WINDOW=15m
RATE_LIMIT_MAX_REQUESTS=100

# Status System
ELITE_THRESHOLD=500
RARE_THRESHOLD=1000
STATUS_CALCULATION_INTERVAL=1h
```

## API Documentation

### gRPC Service Definition

The service implements the following main endpoints:

#### CreateUser
Creates a new user profile with specified preferences.
```protobuf
rpc CreateUser(CreateUserRequest) returns (User);
```

#### UpdateUser
Updates an existing user's profile information.
```protobuf
rpc UpdateUser(UpdateUserRequest) returns (User);
```

#### GetNearbyUsers
Retrieves users within specified radius and filters.
```protobuf
rpc GetNearbyUsers(GetNearbyUsersRequest) returns (GetNearbyUsersResponse);
```

#### UpdateLocation
Updates user's current location.
```protobuf
rpc UpdateLocation(UpdateLocationRequest) returns (google.protobuf.Empty);
```

#### UpdateStatus
Updates user's status level based on activity.
```protobuf
rpc UpdateStatus(UpdateStatusRequest) returns (User);
```

## Status System

### Status Levels
- Regular: Default status
- Elite: >500 points/week
- Rare: >1000 points/week

### Point System
- Tag Creation: 10 points
- User Interaction: 5 points
- Commerce Activity: 20 points

## Security

### Authentication Flow
1. Client authentication via JWT
2. Token validation middleware
3. Refresh token rotation
4. Rate limiting per endpoint

### Security Measures
- JWT with short expiry (1 hour)
- Refresh tokens with rotation
- Rate limiting with Redis
- Input validation and sanitization
- Helmet security headers
- XSS protection
- CORS configuration

## Performance Optimization

### Caching Strategy
- User profiles: 1 hour TTL
- Location data: 30 seconds TTL
- Status calculations: 5 minutes TTL

### Database Optimization
- Indexed queries
- Geospatial indexing
- Connection pooling
- Query optimization

## Deployment

### Docker Deployment
```bash
npm run docker:build
docker run -p 50051:50051 user-service
```

### Kubernetes Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
      - name: user-service
        image: user-service:latest
        ports:
        - containerPort: 50051
        resources:
          limits:
            cpu: "1"
            memory: "2Gi"
          requests:
            cpu: "500m"
            memory: "1Gi"
        livenessProbe:
          grpc:
            port: 50051
          initialDelaySeconds: 30
          periodSeconds: 30
```

## Monitoring

### Metrics
- Request latency
- Error rates
- Active connections
- Cache hit rates
- Status distribution
- User activity metrics

### Health Checks
- Database connectivity
- Redis connectivity
- Memory usage
- CPU usage
- Response times

## Troubleshooting

### Common Issues

1. Connection Errors
```bash
# Check service health
grpc_health_probe -addr=localhost:50051
```

2. Performance Issues
```bash
# Monitor service metrics
curl localhost:9090/metrics
```

3. Authentication Failures
- Verify JWT configuration
- Check token expiration
- Validate refresh token rotation

## Development

### Running Tests
```bash
npm test
```

### Linting
```bash
npm run lint
```

### Security Audit
```bash
npm run security:audit
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to the branch
5. Create a Pull Request

## License

Copyright © 2023 Spatial Tag Platform