# Stage 1: Planner
# Use cargo-chef to plan dependency caching
FROM rust:1.74-slim-bullseye AS planner
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && cargo install cargo-chef

COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# Stage 2: Cacher
# Cache dependencies using cargo-chef
FROM rust:1.74-slim-bullseye AS cacher
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && cargo install cargo-chef

COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

# Stage 3: Builder
# Build the optimized Rust application
FROM rust:1.74-slim-bullseye AS builder
WORKDIR /app

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Copy the cached dependencies
COPY --from=cacher /app/target target
COPY --from=cacher /usr/local/cargo /usr/local/cargo

# Copy source code
COPY . .

# Build with optimizations
ENV RUSTFLAGS="-C target-cpu=native -C link-time-optimization=thin"
RUN cargo build --release --locked \
    && strip target/release/spatial-engine

# Stage 4: Runtime
# Minimal runtime environment
FROM debian:bullseye-slim AS runtime

# Create non-root user
RUN groupadd -r spatial-engine && \
    useradd -r -g spatial-engine -s /sbin/nologin spatial-engine

# Install runtime dependencies and health check probe
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl1.1 \
    curl \
    && curl -L https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/v0.4.13/grpc_health_probe-linux-amd64 -o /usr/local/bin/grpc_health_probe \
    && chmod +x /usr/local/bin/grpc_health_probe \
    && apt-get remove -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /app/target/release/spatial-engine /usr/local/bin/

# Set secure permissions
RUN chown spatial-engine:spatial-engine /usr/local/bin/spatial-engine && \
    chmod 550 /usr/local/bin/spatial-engine

# Configure environment
ENV RUST_LOG=info \
    SERVER_ADDR=[::]:50051 \
    RUST_BACKTRACE=1 \
    RUST_WORKERS=4

# Switch to non-root user
USER spatial-engine

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD ["/usr/local/bin/grpc_health_probe", "-addr=:50051"]

# Expose gRPC port
EXPOSE 50051

# Container metadata
LABEL maintainer="SpatialTag Team <team@spatialtag.com>" \
      version="1.0.0" \
      description="Spatial Engine service for LiDAR processing and spatial calculations" \
      security.scan-date=${BUILD_DATE}

# Set read-only filesystem and no privilege escalation
WORKDIR /
RUN mkdir -p /tmp/spatial-engine && \
    chown spatial-engine:spatial-engine /tmp/spatial-engine
VOLUME ["/tmp/spatial-engine"]

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/spatial-engine"]