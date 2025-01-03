#!/bin/bash

# SSL/TLS Certificate Renewal Script
# Version: 1.0.0
# Dependencies:
# - aws-cli v2.0+
# - kubectl v1.27+
# - certbot v2.0+

set -euo pipefail

# Global Configuration
DOMAINS="api.spatialtag.com monitoring.spatialtag.com auth.spatialtag.com"
CERT_PATH="/etc/letsencrypt/live"
BACKUP_PATH="/etc/ssl/backup"
AWS_REGION="us-east-1"
NAMESPACE="spatial-tag"
TLS_VERSION="TLSv1.3"
RETRY_MAX=3
BACKUP_RETENTION_DAYS=30
ALERT_WEBHOOK="https://hooks.slack.com/services/xxx"

# Logging Configuration
LOG_FILE="/var/log/ssl-cert-renewal.log"
AUDIT_LOG="/var/log/ssl-cert-audit.log"

log() {
    local level=$1
    local message=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${timestamp}|${level}|ssl-cert-renewal|${message}" | tee -a "$LOG_FILE"
    
    # Send critical errors to Slack
    if [[ "$level" == "ERROR" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 SSL Cert Renewal Error: ${message}\"}" \
            "$ALERT_WEBHOOK"
    fi
}

audit_log() {
    local action=$1
    local details=$2
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${timestamp}|AUDIT|${action}|${details}" >> "$AUDIT_LOG"
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check required tools
    for cmd in aws kubectl certbot openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command not found: $cmd"
            return 1
        fi
    done
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "Invalid AWS credentials"
        return 1
    fi
    
    # Check kubectl access
    if ! kubectl auth can-i get secrets -n "$NAMESPACE" &> /dev/null; then
        log "ERROR" "Insufficient Kubernetes permissions"
        return 1
    }
    
    # Verify directories
    for dir in "$CERT_PATH" "$BACKUP_PATH"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "INFO" "Created directory: $dir"
        fi
    done
    
    log "INFO" "Prerequisites check completed successfully"
    return 0
}

renew_certificates() {
    local domain
    local temp_dir
    local result=0
    
    log "INFO" "Starting certificate renewal process"
    temp_dir=$(mktemp -d)
    
    for domain in $DOMAINS; do
        log "INFO" "Processing domain: $domain"
        
        # Attempt certificate renewal
        if ! certbot renew --cert-name "$domain" \
            --dns-route53 \
            --preferred-challenges dns-01 \
            --non-interactive \
            --agree-tos \
            --deploy-hook "touch $temp_dir/$domain.renewed" \
            --tls-sni-01-port 443; then
            log "ERROR" "Certificate renewal failed for $domain"
            result=1
            continue
        fi
        
        # Verify TLS version and certificate validity
        if ! openssl x509 -in "$CERT_PATH/$domain/fullchain.pem" -text | grep -q "$TLS_VERSION"; then
            log "ERROR" "Invalid TLS version for $domain"
            result=1
            continue
        fi
        
        audit_log "CERT_RENEWAL" "Successfully renewed certificate for $domain"
    done
    
    rm -rf "$temp_dir"
    return $result
}

update_kubernetes_secrets() {
    local domain=$1
    local secret_name="tls-cert-${domain//./-}"
    local temp_secret_name="${secret_name}-new"
    
    log "INFO" "Updating Kubernetes secrets for $domain"
    
    # Create new secret
    if ! kubectl create secret tls "$temp_secret_name" \
        --cert="$CERT_PATH/$domain/fullchain.pem" \
        --key="$CERT_PATH/$domain/privkey.pem" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -; then
        log "ERROR" "Failed to create new secret for $domain"
        return 1
    fi
    
    # Update deployments
    local deployments
    deployments=$(kubectl get deployments -n "$NAMESPACE" -l "tls-cert=$secret_name" -o name)
    for deployment in $deployments; do
        if ! kubectl patch "$deployment" -n "$NAMESPACE" \
            -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"cert-update\":\"$(date +%s)\"}}}}}" \
            --record; then
            log "ERROR" "Failed to update deployment $deployment"
            return 1
        fi
    done
    
    # Verify deployment rollout
    for deployment in $deployments; do
        if ! kubectl rollout status "$deployment" -n "$NAMESPACE" --timeout=5m; then
            log "ERROR" "Deployment rollout failed for $deployment"
            return 1
        fi
    done
    
    # Clean up old secret
    kubectl delete secret "$secret_name" -n "$NAMESPACE" --ignore-not-found
    kubectl rename secret "$temp_secret_name" "$secret_name" -n "$NAMESPACE"
    
    audit_log "SECRET_UPDATE" "Updated Kubernetes secrets for $domain"
    return 0
}

update_acm_certificates() {
    local certificate_path=$1
    local cert_arn
    
    log "INFO" "Updating ACM certificate from $certificate_path"
    
    # Import certificate to ACM
    cert_arn=$(aws acm import-certificate \
        --certificate-chain "file://$certificate_path/chain.pem" \
        --certificate "file://$certificate_path/cert.pem" \
        --private-key "file://$certificate_path/privkey.pem" \
        --region "$AWS_REGION" \
        --output text \
        --query 'CertificateArn')
    
    if [[ -z "$cert_arn" ]]; then
        log "ERROR" "Failed to import certificate to ACM"
        return 1
    fi
    
    # Update ALB listeners
    local listeners
    listeners=$(aws elbv2 describe-listeners \
        --region "$AWS_REGION" \
        --query 'Listeners[?Protocol==`HTTPS`].ListenerArn' \
        --output text)
    
    for listener in $listeners; do
        if ! aws elbv2 modify-listener \
            --listener-arn "$listener" \
            --certificates "CertificateArn=$cert_arn" \
            --region "$AWS_REGION"; then
            log "ERROR" "Failed to update listener $listener"
            return 1
        fi
    done
    
    audit_log "ACM_UPDATE" "Updated ACM certificate: $cert_arn"
    return 0
}

backup_certificates() {
    local domain=$1
    local backup_dir="$BACKUP_PATH/$(date +%Y%m%d_%H%M%S)_${domain}"
    
    log "INFO" "Backing up certificates for $domain"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Copy certificates
    cp -r "$CERT_PATH/$domain"/* "$backup_dir/"
    
    # Generate checksum
    (cd "$backup_dir" && find . -type f -exec sha256sum {} \; > checksums.txt)
    
    # Clean old backups
    find "$BACKUP_PATH" -type d -mtime +"$BACKUP_RETENTION_DAYS" -exec rm -rf {} \;
    
    audit_log "BACKUP" "Created backup for $domain at $backup_dir"
    return 0
}

main() {
    local exit_code=0
    
    log "INFO" "Starting SSL certificate renewal process"
    
    # Check prerequisites
    if ! check_prerequisites; then
        log "ERROR" "Prerequisites check failed"
        return 1
    fi
    
    # Process each domain
    for domain in $DOMAINS; do
        # Backup existing certificates
        if ! backup_certificates "$domain"; then
            log "WARNING" "Backup failed for $domain"
        fi
        
        # Renew certificates
        if ! renew_certificates; then
            log "ERROR" "Certificate renewal failed for $domain"
            exit_code=1
            continue
        fi
        
        # Update Kubernetes secrets
        if ! update_kubernetes_secrets "$domain"; then
            log "ERROR" "Kubernetes secret update failed for $domain"
            exit_code=1
            continue
        fi
        
        # Update ACM certificates
        if ! update_acm_certificates "$CERT_PATH/$domain"; then
            log "ERROR" "ACM certificate update failed for $domain"
            exit_code=1
            continue
        fi
        
        log "INFO" "Successfully processed domain: $domain"
    done
    
    if [[ $exit_code -eq 0 ]]; then
        log "INFO" "Certificate renewal process completed successfully"
    else
        log "ERROR" "Certificate renewal process completed with errors"
    fi
    
    return $exit_code
}

# Execute main function
main "$@"