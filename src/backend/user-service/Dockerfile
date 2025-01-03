# Stage 1: Builder
FROM node:20-alpine AS builder

# Set working directory
WORKDIR /usr/src/app

# Install build dependencies
RUN apk add --no-cache python3 make g++ git

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install all dependencies including devDependencies
RUN npm ci

# Copy source code
COPY src/ ./src/
COPY proto/ ./proto/

# Generate Prisma client and protobuf types
RUN npm run proto:gen

# Build TypeScript code
RUN npm run build

# Run security audit
RUN npm run security:audit

# Stage 2: Production
FROM node:20-alpine

# Set working directory
WORKDIR /usr/src/app

# Install production dependencies
RUN apk add --no-cache tini

# Create non-root user/group
RUN addgroup -S nodegroup && \
    adduser -S nodeuser -G nodegroup

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production && \
    npm cache clean --force

# Copy built files from builder stage
COPY --from=builder /usr/src/app/dist ./dist
COPY --from=builder /usr/src/app/proto ./proto

# Set proper permissions
RUN chown -R nodeuser:nodegroup /usr/src/app && \
    chmod -R 644 /usr/src/app && \
    find /usr/src/app -type d -exec chmod 755 {} \;

# Configure Node.js garbage collection and memory limits
ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=2048 --max-semi-space-size=512 --gc-interval=100"

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD node dist/src/healthcheck.js

# Expose gRPC port
EXPOSE 50051

# Switch to non-root user
USER nodeuser

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--"]

# Start the service with resource constraints
CMD ["node", "--cpu-quota=100000", "--memory-max=2048", "dist/src/app.js"]

# Labels for container metadata
LABEL maintainer="SpatialTag Team" \
      version="1.0.0" \
      description="User Service for SpatialTag Platform" \
      org.opencontainers.image.source="https://github.com/spatialtag/user-service"