# Stage 1: Builder
FROM python:3.11-slim AS builder

# Set build arguments and environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    POETRY_VERSION=1.6.1 \
    POETRY_HOME=/opt/poetry \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_NO_INTERACTION=1

# Install system build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry for dependency management
RUN curl -sSL https://install.python-poetry.org | python3 -
ENV PATH="${POETRY_HOME}/bin:$PATH"

# Set up working directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml poetry.lock ./
COPY requirements.txt ./

# Install dependencies
RUN python -m venv /app/.venv && \
    . /app/.venv/bin/activate && \
    pip install --no-cache-dir -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

# Set runtime environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=50051 \
    APP_ENV=production

# Create non-root user and group
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -s /sbin/nologin -M appuser && \
    mkdir -p /app && \
    chown appuser:appgroup /app

# Install runtime dependencies and grpc-health-probe
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && curl -L https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/v0.4.19/grpc_health_probe-linux-amd64 -o /usr/local/bin/grpc-health-probe \
    && chmod +x /usr/local/bin/grpc-health-probe \
    && apt-get remove -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /tmp/data \
    && chown appuser:appgroup /tmp/data

WORKDIR /app

# Copy virtual environment and application code from builder
COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup ./src ./src

# Set secure permissions
RUN chmod -R 550 /app/src && \
    chmod -R 550 /app/.venv

# Set up tmpfs volume for temporary data
VOLUME ["/tmp/data"]

# Configure health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/grpc-health-probe", "-addr=:50051"]

# Set resource limits
ENV MEMORY_LIMIT=512M \
    CPU_LIMIT=1.0

# Set security options
LABEL maintainer="SpatialTag DevOps" \
      version="1.0.0" \
      security.pci-dss.compliant="true"

# Switch to non-root user
USER appuser:appgroup

# Expose gRPC port
EXPOSE 50051

# Set entrypoint
ENTRYPOINT ["/app/.venv/bin/python", "-m", "src.api.grpc_server"]

# Enable security features
SECURITY_OPT ["no-new-privileges=true", "seccomp=unconfined", "apparmor=docker-default"]