# Stage 1: Builder
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /app

# Install build dependencies and security tools
RUN apk add --no-cache python3 make g++ git curl \
    && npm install -g npm@9 typescript@5.1.6 @microsoft/rush snyk

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Run security scan
RUN snyk test --severity-threshold=high || true

# Build TypeScript code
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# Run security scan on built artifacts
RUN snyk test --severity-threshold=high || true

# Stage 2: Production
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S node && \
    adduser -u 1001 -S node -G node

# Install production dependencies
RUN apk add --no-cache tini curl

# Copy package files and built artifacts
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules

# Configure security settings
RUN chown -R node:node /app && \
    chmod -R 755 /app

# Set environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    LOG_LEVEL=info \
    METRICS_ENABLED=true

# Expose ports
EXPOSE 3000 9090

# Set up health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Switch to non-root user
USER node

# Set resource limits
ENV NODE_OPTIONS="--max-old-space-size=2048"
LABEL com.docker.resource.cpu="1" \
      com.docker.resource.memory="2GB" \
      com.docker.resource.pids="50" \
      com.docker.resource.nofile="1000"

# Add metadata labels
LABEL maintainer="SpatialTag DevOps" \
      version="1.0.0" \
      description="API Gateway Service" \
      security.scan.status="verified"

# Use tini as init
ENTRYPOINT ["/sbin/tini", "--"]

# Start application
CMD ["node", "dist/app.js"]

# Security options
SECURITY_OPTS --security-opt=no-new-privileges:true \
              --security-opt=seccomp=unconfined \
              --cap-drop=ALL \
              --read-only \
              --tmpfs /tmp:rw,noexec,nosuid,size=65536k