#!/bin/bash

# Spatial Tag Platform Database Backup Script
# Version: 1.0.0
# Dependencies:
# - postgresql-client v15
# - mongodb-database-tools v6.0
# - redis-tools v7.0
# - aws-cli v2.0
# - openssl v3.0

set -euo pipefail

# Global Configuration
BACKUP_ROOT="/var/backups/spatial_tag"
RETENTION_DAYS=30
S3_BUCKET="spatial-tag-backups"
ENCRYPTION_KEY_PATH="/etc/spatial_tag/backup_key.asc"
LOG_PATH="/var/log/spatial_tag/backups"
NOTIFICATION_WEBHOOK="https://alerts.spatial_tag.com/backup_status"
BACKUP_CHUNK_SIZE="100M"
MAX_PARALLEL_UPLOADS=4

# Timestamp for backup identification
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ID="backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_ROOT}/${BACKUP_ID}"

# Logging configuration
mkdir -p "${LOG_PATH}"
exec 1> >(tee -a "${LOG_PATH}/${BACKUP_ID}.log")
exec 2>&1

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    log "ERROR: $1"
    notify_error "$1"
    exit 1
}

validate_environment() {
    log "Validating environment..."
    
    # Check required tools
    for cmd in pg_dump mongodump redis-cli aws openssl zstd; do
        command -v "$cmd" >/dev/null 2>&1 || error "Required tool $cmd not found"
    done
    
    # Verify directories and permissions
    [[ -d "$BACKUP_ROOT" ]] || error "Backup root directory does not exist"
    [[ -w "$BACKUP_ROOT" ]] || error "Backup root directory not writable"
    [[ -f "$ENCRYPTION_KEY_PATH" ]] || error "Encryption key not found"
    [[ -r "$ENCRYPTION_KEY_PATH" ]] || error "Encryption key not readable"
    
    # Verify AWS credentials
    aws sts get-caller-identity >/dev/null 2>&1 || error "AWS credentials not valid"
    
    # Create backup directory
    mkdir -p "$BACKUP_PATH" || error "Failed to create backup directory"
    
    log "Environment validation completed"
    return 0
}

backup_postgresql() {
    local db_host="$1"
    local db_name="$2"
    local backup_file="${BACKUP_PATH}/${db_name}_${TIMESTAMP}.sql.gz"
    
    log "Starting PostgreSQL backup for $db_name"
    
    # Test connection
    PGCONNECT_TIMEOUT=10 pg_isready -h "$db_host" || error "PostgreSQL connection failed"
    
    # Create backup with compression and progress monitoring
    pg_dump -h "$db_host" "$db_name" \
        --format=custom \
        --compress=9 \
        --verbose \
        --file="$backup_file" || error "PostgreSQL backup failed"
    
    # Encrypt backup
    openssl enc -aes-256-gcm -salt \
        -in "$backup_file" \
        -out "${backup_file}.enc" \
        -pass file:"$ENCRYPTION_KEY_PATH" || error "Backup encryption failed"
    
    # Calculate checksum
    sha256sum "${backup_file}.enc" > "${backup_file}.enc.sha256"
    
    # Upload to S3 with server-side encryption
    aws s3 cp "${backup_file}.enc" \
        "s3://${S3_BUCKET}/postgresql/${db_name}/${BACKUP_ID}/" \
        --expected-size $(stat -f%z "${backup_file}.enc") \
        --sse AES256 || error "S3 upload failed for PostgreSQL backup"
    
    # Cleanup local files
    rm -f "$backup_file" "${backup_file}.enc"
    
    log "PostgreSQL backup completed for $db_name"
    return 0
}

backup_mongodb() {
    local mongo_uri="$1"
    local backup_dir="${BACKUP_PATH}/mongodb"
    
    log "Starting MongoDB backup"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Perform backup with compression
    mongodump --uri="$mongo_uri" \
        --out="$backup_dir" \
        --gzip || error "MongoDB backup failed"
    
    # Create tarball of backup directory
    tar -czf "${backup_dir}.tar.gz" -C "$backup_dir" . || error "MongoDB backup compression failed"
    
    # Encrypt backup
    openssl enc -aes-256-gcm -salt \
        -in "${backup_dir}.tar.gz" \
        -out "${backup_dir}.tar.gz.enc" \
        -pass file:"$ENCRYPTION_KEY_PATH" || error "MongoDB backup encryption failed"
    
    # Calculate checksum
    sha256sum "${backup_dir}.tar.gz.enc" > "${backup_dir}.tar.gz.enc.sha256"
    
    # Upload to S3 with multipart
    aws s3 cp "${backup_dir}.tar.gz.enc" \
        "s3://${S3_BUCKET}/mongodb/${BACKUP_ID}/" \
        --expected-size $(stat -f%z "${backup_dir}.tar.gz.enc") \
        --sse AES256 || error "S3 upload failed for MongoDB backup"
    
    # Cleanup local files
    rm -rf "$backup_dir" "${backup_dir}.tar.gz" "${backup_dir}.tar.gz.enc"
    
    log "MongoDB backup completed"
    return 0
}

backup_redis() {
    local redis_host="$1"
    local redis_port="$2"
    local backup_file="${BACKUP_PATH}/redis_${TIMESTAMP}.rdb"
    
    log "Starting Redis backup"
    
    # Trigger BGSAVE
    redis-cli -h "$redis_host" -p "$redis_port" BGSAVE || error "Redis BGSAVE failed"
    
    # Wait for BGSAVE to complete
    while true; do
        if redis-cli -h "$redis_host" -p "$redis_port" INFO persistence | grep -q "rdb_bgsave_in_progress:0"; then
            break
        fi
        sleep 1
    done
    
    # Copy dump file
    redis-cli -h "$redis_host" -p "$redis_port" --rdb "$backup_file" || error "Redis backup failed"
    
    # Compress backup
    zstd -19 "$backup_file" -o "${backup_file}.zst" || error "Redis backup compression failed"
    
    # Encrypt backup
    openssl enc -aes-256-gcm -salt \
        -in "${backup_file}.zst" \
        -out "${backup_file}.zst.enc" \
        -pass file:"$ENCRYPTION_KEY_PATH" || error "Redis backup encryption failed"
    
    # Calculate checksum
    sha256sum "${backup_file}.zst.enc" > "${backup_file}.zst.enc.sha256"
    
    # Upload to S3
    aws s3 cp "${backup_file}.zst.enc" \
        "s3://${S3_BUCKET}/redis/${BACKUP_ID}/" \
        --expected-size $(stat -f%z "${backup_file}.zst.enc") \
        --sse AES256 || error "S3 upload failed for Redis backup"
    
    # Cleanup local files
    rm -f "$backup_file" "${backup_file}.zst" "${backup_file}.zst.enc"
    
    log "Redis backup completed"
    return 0
}

cleanup_old_backups() {
    log "Starting backup cleanup"
    
    # Calculate cutoff date
    CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d)
    
    # List and delete old backups
    aws s3 ls "s3://${S3_BUCKET}" --recursive | while read -r line; do
        backup_date=$(echo "$line" | awk '{print $4}' | grep -oP '\d{8}')
        if [[ "$backup_date" < "$CUTOFF_DATE" ]]; then
            aws s3 rm "s3://${S3_BUCKET}/${line##* }" || log "Failed to remove old backup: ${line##* }"
        fi
    done
    
    log "Backup cleanup completed"
    return 0
}

monitor_backup_status() {
    local start_time=$(date +%s)
    local backup_size=0
    
    # Calculate total backup size
    backup_size=$(du -sb "$BACKUP_PATH" | awk '{print $1}')
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Send notification
    curl -X POST "$NOTIFICATION_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{
            \"backup_id\": \"$BACKUP_ID\",
            \"status\": \"completed\",
            \"duration_seconds\": $duration,
            \"size_bytes\": $backup_size,
            \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"
        }" || log "Failed to send backup notification"
    
    return 0
}

# Main execution
main() {
    log "Starting database backup process"
    
    validate_environment || exit 1
    
    # Backup PostgreSQL databases
    backup_postgresql "postgres-primary.spatial_tag.internal" "spatial_tag_main" || exit 1
    
    # Backup MongoDB
    backup_mongodb "mongodb://mongo-primary.spatial_tag.internal:27017" || exit 1
    
    # Backup Redis
    backup_redis "redis-primary.spatial_tag.internal" "6379" || exit 1
    
    # Monitor and report status
    monitor_backup_status || log "Status monitoring failed"
    
    # Cleanup old backups
    cleanup_old_backups || log "Backup cleanup failed"
    
    log "Backup process completed successfully"
    exit 0
}

# Execute main function
main