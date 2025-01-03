# Stage 1: Spatial Engine Builder
FROM rust:1.74-slim AS spatial-engine-builder
WORKDIR /app/spatial-engine

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files first for better caching
COPY spatial-engine/Cargo.toml spatial-engine/Cargo.lock ./

# Build dependencies only
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy source code and build
COPY spatial-engine/src ./src
RUN cargo build --release

# Stage 2: Tag Service Builder
FROM golang:1.21-alpine AS tag-service-builder
WORKDIR /app/tag-service

# Install build essentials
RUN apk add --no-cache ca-certificates git

# Copy dependency files
COPY tag-service/go.mod tag-service/go.sum ./

# Download dependencies
RUN go mod download

# Copy source code and build
COPY tag-service/. .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o tag-service

# Stage 3: User Service Builder
FROM node:20-alpine AS user-service-builder
WORKDIR /app/user-service

# Copy dependency files
COPY user-service/package*.json ./

# Install production dependencies
RUN npm ci --only=production

# Copy source code and build
COPY user-service/. .
RUN npm run build

# Stage 4: Commerce Service Builder
FROM python:3.11-slim AS commerce-service-builder
WORKDIR /app/commerce-service

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files
COPY commerce-service/requirements.txt .

# Install production dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY commerce-service/. .

# Stage 5: Final Runtime Image
FROM debian:bullseye-slim

# Create non-root user
RUN groupadd -r spatialapp && useradd -r -g spatialapp -s /sbin/nologin spatialapp

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl1.1 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy built artifacts from builder stages
COPY --from=spatial-engine-builder /app/spatial-engine/target/release/spatial-engine ./spatial-engine/
COPY --from=tag-service-builder /app/tag-service/tag-service ./tag-service/
COPY --from=user-service-builder /app/user-service/dist ./user-service/
COPY --from=commerce-service-builder /app/commerce-service ./commerce-service/

# Set environment variables
ENV NODE_ENV=development \
    RUST_LOG=debug \
    GO_ENV=development \
    PYTHONUNBUFFERED=1 \
    RUST_BACKTRACE=1 \
    GOMAXPROCS=1 \
    NODE_OPTIONS="--max-old-space-size=2048"

# Set permissions
RUN chown -R spatialapp:spatialapp /app && \
    chmod -R 550 /app

# Expose service ports
EXPOSE 50051 50052 50053 50054

# Set resource limits
LABEL com.spatial.resource.limits.spatial-engine.cpu="2" \
      com.spatial.resource.limits.spatial-engine.memory="4GB" \
      com.spatial.resource.limits.tag-service.cpu="1" \
      com.spatial.resource.limits.tag-service.memory="2GB" \
      com.spatial.resource.limits.user-service.cpu="1" \
      com.spatial.resource.limits.user-service.memory="2GB" \
      com.spatial.resource.limits.commerce-service.cpu="1" \
      com.spatial.resource.limits.commerce-service.memory="2GB"

# Set security options
USER spatialapp
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/app/spatial-engine/health-check"]

# Set security limits
SECURITY_OPT ["no-new-privileges:true", "seccomp=unconfined"]

# Drop capabilities and set ulimits
STOPSIGNAL SIGTERM

# Start services (using a shell script as entrypoint)
COPY --chown=spatialapp:spatialapp docker-entrypoint.sh /app/
RUN chmod 550 /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]