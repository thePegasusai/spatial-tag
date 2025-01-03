#!/bin/bash

# Database Initialization Script for Spatial Tag Platform
# Version: 1.0.0
# Requires: PostgreSQL 15+, MongoDB 6.0+, Redis 7.0+, Vault 1.13+

set -euo pipefail

# Global Configuration
POSTGRES_MIGRATIONS_DIR="../src/backend/migrations"
REQUIRED_PG_EXTENSIONS=("uuid-ossp" "postgis" "pg_stat_statements")
MONGODB_COLLECTIONS=("tags" "analytics" "audit_logs")
REDIS_CONFIG="{maxmemory: '2gb', maxmemory-policy: 'allkeys-lru', notify-keyspace-events: 'Ex'}"

# Load environment variables
if [ -f "../src/backend/.env" ]; then
    source "../src/backend/.env"
else
    echo "Error: Environment file not found"
    exit 1
fi

# Validation function for environment and dependencies
validate_environment() {
    local required_tools=("psql" "mongosh" "redis-cli" "vault")
    local required_versions=("15.0" "6.0.0" "7.0.0" "1.13.0")

    for i in "${!required_tools[@]}"; do
        if ! command -v "${required_tools[$i]}" &> /dev/null; then
            echo "Error: ${required_tools[$i]} is required but not installed"
            exit 1
        fi
        
        # Version check logic for each tool
        case "${required_tools[$i]}" in
            psql)
                version=$(psql --version | awk '{print $3}' | cut -d. -f1,2)
                ;;
            mongosh)
                version=$(mongosh --version | awk '{print $3}' | cut -d. -f1,2)
                ;;
            redis-cli)
                version=$(redis-cli --version | cut -d= -f2 | cut -d. -f1,2)
                ;;
            vault)
                version=$(vault version | cut -d' ' -f2 | cut -d'v' -f2 | cut -d. -f1,2)
                ;;
        esac

        if ! [[ "$version" > "${required_versions[$i]}" ]]; then
            echo "Error: ${required_tools[$i]} version ${required_versions[$i]}+ required"
            exit 1
        fi
    done
}

# Initialize PostgreSQL database
init_postgresql() {
    local db_host=$1
    local db_name=$2
    local db_user=$3

    echo "Initializing PostgreSQL database..."

    # Create database if not exists
    psql -h "$db_host" -U "$db_user" -c "CREATE DATABASE $db_name" || true

    # Enable required extensions
    for extension in "${REQUIRED_PG_EXTENSIONS[@]}"; do
        psql -h "$db_host" -U "$db_user" -d "$db_name" -c "CREATE EXTENSION IF NOT EXISTS \"$extension\";"
    done

    # Apply migrations
    for migration in "$POSTGRES_MIGRATIONS_DIR"/*.up.sql; do
        echo "Applying migration: $migration"
        psql -h "$db_host" -U "$db_user" -d "$db_name" -f "$migration"
    done

    # Configure security settings
    psql -h "$db_host" -U "$db_user" -d "$db_name" <<-EOSQL
        ALTER SYSTEM SET ssl = on;
        ALTER SYSTEM SET ssl_ciphers = 'HIGH:!aNULL';
        ALTER SYSTEM SET log_statement = 'mod';
        ALTER SYSTEM SET log_min_duration_statement = 1000;
        SELECT pg_reload_conf();
EOSQL

    # Set up monitoring
    psql -h "$db_host" -U "$db_user" -d "$db_name" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
        ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
        ALTER SYSTEM SET pg_stat_statements.track = 'all';
EOSQL
}

# Initialize MongoDB
init_mongodb() {
    local mongo_uri=$1
    local db_name=$2

    echo "Initializing MongoDB..."

    # Create collections and indexes
    mongosh "$mongo_uri" <<-EOMONGO
        use $db_name;
        
        // Create tags collection with schema validation
        db.createCollection("tags", {
            validator: {
                \$jsonSchema: {
                    bsonType: "object",
                    required: ["location", "content", "expiration"],
                    properties: {
                        location: {
                            bsonType: "object",
                            required: ["type", "coordinates"],
                            properties: {
                                type: { enum: ["Point"] },
                                coordinates: { bsonType: "array" }
                            }
                        },
                        content: { bsonType: "object" },
                        expiration: { bsonType: "date" }
                    }
                }
            }
        });

        // Create spatial index for tag locations
        db.tags.createIndex({ location: "2dsphere" });
        
        // Create TTL index for tag expiration
        db.tags.createIndex({ expiration: 1 }, { expireAfterSeconds: 0 });
        
        // Enable audit logging
        db.setProfilingLevel(1, { slowms: 100 });
EOMONGO
}

# Initialize Redis
init_redis() {
    local redis_host=$1
    local redis_port=$2

    echo "Initializing Redis..."

    # Configure Redis settings
    redis-cli -h "$redis_host" -p "$redis_port" <<-EOREDIS
        CONFIG SET maxmemory 2gb
        CONFIG SET maxmemory-policy allkeys-lru
        CONFIG SET notify-keyspace-events Ex
        CONFIG SET appendonly yes
        CONFIG SET appendfsync everysec
        CONFIG REWRITE
EOREDIS

    # Set up monitoring
    redis-cli -h "$redis_host" -p "$redis_port" <<-EOREDIS
        CONFIG SET latency-monitor-threshold 100
        CONFIG SET slowlog-log-slower-than 10000
EOREDIS
}

# Set up monitoring for all databases
setup_monitoring() {
    echo "Setting up database monitoring..."

    # PostgreSQL monitoring
    psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
        CREATE EXTENSION IF NOT EXISTS pg_stat_monitor;
        
        -- Create monitoring user with restricted permissions
        CREATE USER monitoring WITH PASSWORD '${MONITORING_PASSWORD}';
        GRANT CONNECT ON DATABASE "${DB_NAME}" TO monitoring;
        GRANT SELECT ON pg_stat_statements TO monitoring;
EOSQL

    # MongoDB monitoring
    mongosh "$MONGO_URI" <<-EOMONGO
        use admin;
        db.createUser({
            user: "monitoring",
            pwd: "${MONITORING_PASSWORD}",
            roles: [ { role: "clusterMonitor", db: "admin" } ]
        });
EOMONGO

    # Redis monitoring
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" <<-EOREDIS
        CONFIG SET notify-keyspace-events AKE
        CONFIG SET latency-monitor-threshold 100
EOREDIS
}

# Main execution
main() {
    echo "Starting database initialization..."

    # Validate environment
    validate_environment

    # Initialize PostgreSQL
    init_postgresql "$DB_HOST" "$DB_NAME" "$DB_USER"

    # Initialize MongoDB
    init_mongodb "$MONGO_URI" "$DB_NAME"

    # Initialize Redis
    init_redis "$REDIS_HOST" "$REDIS_PORT"

    # Setup monitoring
    setup_monitoring

    echo "Database initialization completed successfully"
}

# Execute main function
main