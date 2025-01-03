#!/bin/bash

# Monitoring Stack Setup Script for Spatial Tag Platform
# Version: 1.0.0
# This script automates the deployment and configuration of the monitoring stack
# including Prometheus, Grafana, ELK Stack, and Jaeger with enhanced LiDAR metrics

set -euo pipefail

# Global Variables
PROMETHEUS_VERSION="2.45.0"
GRAFANA_VERSION="10.0.3"
ELASTICSEARCH_VERSION="8.9.0"
KIBANA_VERSION="8.9.0"
JAEGER_VERSION="1.47.0"
RETRY_ATTEMPTS=3
HEALTH_CHECK_TIMEOUT=300
BACKUP_RETENTION_DAYS=30

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling function
handle_error() {
    log "${RED}Error occurred in script at line $1${NC}"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Verify prerequisites
verify_prerequisites() {
    log "${YELLOW}Verifying prerequisites...${NC}"
    
    local required_tools=("kubectl" "helm" "docker")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "${RED}Error: $tool is required but not installed.${NC}"
            exit 1
        fi
    done
    
    # Verify Kubernetes connection
    if ! kubectl cluster-info &> /dev/null; then
        log "${RED}Error: Unable to connect to Kubernetes cluster${NC}"
        exit 1
    }
    
    log "${GREEN}Prerequisites verification completed${NC}"
}

# Setup Prometheus
setup_prometheus() {
    local namespace=$1
    local storage_class=$2
    local retention_days=$3
    
    log "${YELLOW}Setting up Prometheus v${PROMETHEUS_VERSION}...${NC}"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Prometheus Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Deploy Prometheus with custom values
    helm upgrade --install prometheus prometheus-community/prometheus \
        --namespace "$namespace" \
        --set server.persistentVolume.storageClass="$storage_class" \
        --set server.retention="$retention_days"d \
        --set server.global.scrape_interval=15s \
        --set server.global.evaluation_interval=15s \
        --values ../monitoring/prometheus/prometheus.yml
        
    # Wait for deployment
    kubectl rollout status deployment/prometheus-server -n "$namespace" --timeout="${HEALTH_CHECK_TIMEOUT}s"
    
    log "${GREEN}Prometheus setup completed${NC}"
}

# Setup Grafana
setup_grafana() {
    local namespace=$1
    local admin_password=$2
    local prometheus_url=$3
    
    log "${YELLOW}Setting up Grafana v${GRAFANA_VERSION}...${NC}"
    
    # Add Grafana Helm repo
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Deploy Grafana with custom values
    helm upgrade --install grafana grafana/grafana \
        --namespace "$namespace" \
        --set adminPassword="$admin_password" \
        --set datasources."datasources\.yaml".apiVersion=1 \
        --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
        --set datasources."datasources\.yaml".datasources[0].type=prometheus \
        --set datasources."datasources\.yaml".datasources[0].url="$prometheus_url" \
        --set dashboardProviders."dashboardproviders\.yaml".apiVersion=1 \
        --set dashboardProviders."dashboardproviders\.yaml".providers[0].name=default \
        --set dashboardProviders."dashboardproviders\.yaml".providers[0].folder="" \
        --set dashboardsConfigMaps.default.spatial-engine-dashboard=../monitoring/grafana/dashboards/spatial-engine.json \
        --set dashboardsConfigMaps.default.services-dashboard=../monitoring/grafana/dashboards/services.json
        
    # Wait for deployment
    kubectl rollout status deployment/grafana -n "$namespace" --timeout="${HEALTH_CHECK_TIMEOUT}s"
    
    log "${GREEN}Grafana setup completed${NC}"
}

# Setup ELK Stack
setup_elk() {
    local namespace=$1
    local storage_class=$2
    local retention_days=$3
    
    log "${YELLOW}Setting up ELK Stack...${NC}"
    
    # Deploy Elasticsearch
    kubectl apply -f - <<EOF
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: spatial-tag-elasticsearch
  namespace: $namespace
spec:
  version: $ELASTICSEARCH_VERSION
  nodeSets:
  - name: default
    count: 3
    config:
      node.store.allow_mmap: false
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: $storage_class
EOF
    
    # Deploy Logstash
    kubectl create configmap logstash-config \
        --from-file=../monitoring/elk/logstash.conf \
        -n "$namespace" --dry-run=client -o yaml | kubectl apply -f -
        
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  namespace: $namespace
spec:
  replicas: 2
  selector:
    matchLabels:
      app: logstash
  template:
    metadata:
      labels:
        app: logstash
    spec:
      containers:
      - name: logstash
        image: docker.elastic.co/logstash/logstash:$ELASTICSEARCH_VERSION
        volumeMounts:
        - name: config-volume
          mountPath: /usr/share/logstash/pipeline/
        resources:
          limits:
            cpu: 1000m
            memory: 2Gi
          requests:
            cpu: 500m
            memory: 1Gi
      volumes:
      - name: config-volume
        configMap:
          name: logstash-config
EOF
    
    # Wait for ELK deployments
    kubectl rollout status deployment/logstash -n "$namespace" --timeout="${HEALTH_CHECK_TIMEOUT}s"
    
    log "${GREEN}ELK Stack setup completed${NC}"
}

# Setup Jaeger
setup_jaeger() {
    local namespace=$1
    local storage_type=$2
    local retention_days=$3
    
    log "${YELLOW}Setting up Jaeger v${JAEGER_VERSION}...${NC}"
    
    # Create Jaeger operator
    kubectl create -f ../monitoring/jaeger/jaeger-all-in-one.yml -n "$namespace"
    
    # Wait for deployment
    kubectl rollout status deployment/spatial-tag-jaeger -n "$namespace" --timeout="${HEALTH_CHECK_TIMEOUT}s"
    
    log "${GREEN}Jaeger setup completed${NC}"
}

# Verify deployment
verify_deployment() {
    local namespace=$1
    local timeout=$2
    
    log "${YELLOW}Verifying monitoring stack deployment...${NC}"
    
    # Check all pods are running
    local end=$((SECONDS + timeout))
    while [ $SECONDS -lt $end ]; do
        if kubectl get pods -n "$namespace" | grep -v Running | grep -v Completed | wc -l | grep -q "^0$"; then
            log "${GREEN}All pods are running successfully${NC}"
            return 0
        fi
        sleep 5
    done
    
    log "${RED}Deployment verification failed${NC}"
    return 1
}

# Main execution
main() {
    local namespace="monitoring"
    local storage_class="standard"
    local admin_password="changeme"
    local prometheus_url="http://prometheus-server:9090"
    
    # Verify prerequisites
    verify_prerequisites
    
    # Setup monitoring components
    setup_prometheus "$namespace" "$storage_class" "$BACKUP_RETENTION_DAYS"
    setup_grafana "$namespace" "$admin_password" "$prometheus_url"
    setup_elk "$namespace" "$storage_class" "$BACKUP_RETENTION_DAYS"
    setup_jaeger "$namespace" "elasticsearch" "$BACKUP_RETENTION_DAYS"
    
    # Verify deployment
    verify_deployment "$namespace" "$HEALTH_CHECK_TIMEOUT"
    
    log "${GREEN}Monitoring stack setup completed successfully${NC}"
}

# Execute main function
main "$@"