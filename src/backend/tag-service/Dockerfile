# Stage 1: Builder
FROM golang:1.21-alpine AS builder

# Set build environment variables
ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

# Install build dependencies
RUN apk add --no-cache \
    ca-certificates \
    git \
    make \
    build-base

WORKDIR /app

# Copy dependency files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download && \
    go mod verify

# Copy source code
COPY . .

# Build optimized binary
RUN go build -ldflags="-w -s" \
    -o /app/tag-service \
    ./cmd/main.go

# Stage 2: Runtime
FROM alpine:3.18

# Install runtime dependencies and security updates
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create non-root user and group
RUN addgroup -g 10001 -S tagservice && \
    adduser -u 10001 -S tagservice -G tagservice

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder --chown=tagservice:tagservice /app/tag-service .

# Set secure permissions
RUN chmod 0555 /app/tag-service && \
    chown -R tagservice:tagservice /app

# Configure health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD ["/app/tag-service", "-health-check"]

# Expose gRPC port
EXPOSE 50051

# Set environment variables
ENV PORT=50051

# Switch to non-root user
USER tagservice:tagservice

# Set resource limits
LABEL com.kubernetes.resource.cpu="1" \
      com.kubernetes.resource.memory="2Gi" \
      com.kubernetes.resource.pids="100"

# Set entrypoint
ENTRYPOINT ["/app/tag-service"]