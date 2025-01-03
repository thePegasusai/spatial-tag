#!/bin/bash

# Spatial Tag iOS Deployment Script
# Version: 1.0.0
# Requires: 
# - fastlane 2.212.2
# - bundler 2.4.22
# - match 2.219.0
# - security-scan-cli 1.5.0

set -euo pipefail
IFS=$'\n\t'

# Global Configuration
WORKSPACE_PATH="../SpatialTag.xcworkspace"
SCHEME_NAME="SpatialTag"
CONFIGURATION="Release"
DEPLOY_TARGET="testflight"
APP_STORE_CONNECT_API_KEY_PATH="./AuthKey.p8"
MIN_IOS_VERSION="15.0"
REQUIRED_DEVICE_CAPABILITY="lidar"
SECURITY_SCAN_LEVEL="high"
CERTIFICATE_PINNING_ENABLED="true"
AUDIT_LOG_PATH="./deployment_audit.log"

# Initialize audit logging
setup_audit_logging() {
    exec 1> >(tee -a "${AUDIT_LOG_PATH}")
    exec 2> >(tee -a "${AUDIT_LOG_PATH}" >&2)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting deployment process"
}

# Enhanced setup of deployment environment
setup_deployment() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting up deployment environment"
    
    # Verify Ruby environment and install dependencies
    if ! command -v bundle &> /dev/null; then
        echo "Error: Bundler not found. Please install bundler 2.4.22"
        exit 1
    }
    
    # Install and verify dependencies
    bundle install --deployment --quiet
    
    # Verify App Store Connect API key
    if [ ! -f "${APP_STORE_CONNECT_API_KEY_PATH}" ]; then
        echo "Error: App Store Connect API key not found at ${APP_STORE_CONNECT_API_KEY_PATH}"
        exit 1
    }
    
    # Configure secure credential storage
    export MATCH_PASSWORD="${MATCH_PASSWORD:-$(openssl rand -base64 32)}"
    export FASTLANE_SKIP_UPDATE_CHECK=1
    export FASTLANE_HIDE_TIMESTAMP=1
    
    # Initialize security configurations
    if [ "${CERTIFICATE_PINNING_ENABLED}" = "true" ]; then
        echo "Configuring certificate pinning..."
        security create-keychain -p "${MATCH_PASSWORD}" build.keychain
    fi
    
    echo "Deployment environment setup completed"
}

# Comprehensive build validation
validate_build() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Validating build requirements"
    
    # Verify LiDAR capability
    if ! grep -q "\"${REQUIRED_DEVICE_CAPABILITY}\"" "../SpatialTag.xcodeproj/project.pbxproj"; then
        echo "Error: Required LiDAR capability not configured in project"
        exit 1
    }
    
    # Run security scan
    bundle exec fastlane security_scan level:"${SECURITY_SCAN_LEVEL}" \
        timeout:1800 \
        fail_on_critical:true
    
    # Verify minimum iOS version
    local current_min_version=$(xcrun xcodebuild -showBuildSettings \
        -workspace "${WORKSPACE_PATH}" \
        -scheme "${SCHEME_NAME}" \
        | grep IPHONEOS_DEPLOYMENT_TARGET \
        | awk '{print $3}')
    
    if [ "${current_min_version}" \< "${MIN_IOS_VERSION}" ]; then
        echo "Error: Minimum iOS version (${current_min_version}) is below required ${MIN_IOS_VERSION}"
        exit 1
    }
    
    echo "Build validation completed successfully"
}

# Enhanced TestFlight deployment
deploy_testflight() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deploying to TestFlight"
    
    # Create deployment checkpoint
    local checkpoint_file="./deployment_checkpoint_$(date +%s)"
    touch "${checkpoint_file}"
    
    # Execute TestFlight deployment
    if ! bundle exec fastlane beta \
        workspace:"${WORKSPACE_PATH}" \
        scheme:"${SCHEME_NAME}" \
        configuration:"${CONFIGURATION}" \
        api_key_path:"${APP_STORE_CONNECT_API_KEY_PATH}"; then
        echo "Error: TestFlight deployment failed"
        rm "${checkpoint_file}"
        exit 1
    fi
    
    echo "TestFlight deployment completed successfully"
    rm "${checkpoint_file}"
}

# Secure App Store deployment
deploy_appstore() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deploying to App Store"
    
    # Verify release requirements
    if [ ! -f "./release_notes.txt" ]; then
        echo "Error: Release notes not found"
        exit 1
    }
    
    # Execute App Store deployment
    if ! bundle exec fastlane release \
        workspace:"${WORKSPACE_PATH}" \
        scheme:"${SCHEME_NAME}" \
        configuration:"${CONFIGURATION}" \
        api_key_path:"${APP_STORE_CONNECT_API_KEY_PATH}"; then
        echo "Error: App Store deployment failed"
        exit 1
    fi
    
    echo "App Store deployment completed successfully"
}

# Secure cleanup of deployment artifacts
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Performing deployment cleanup"
    
    # Archive deployment logs
    if [ -f "${AUDIT_LOG_PATH}" ]; then
        local archive_name="deployment_logs_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "${archive_name}" "${AUDIT_LOG_PATH}" --remove-files
        openssl enc -aes-256-cbc -salt -in "${archive_name}" -out "${archive_name}.enc"
        rm "${archive_name}"
    fi
    
    # Clean sensitive files
    if [ -f "${APP_STORE_CONNECT_API_KEY_PATH}" ]; then
        shred -u "${APP_STORE_CONNECT_API_KEY_PATH}"
    fi
    
    # Clean build artifacts
    bundle exec fastlane clean_build_artifacts
    
    echo "Cleanup completed successfully"
}

# Main deployment flow
main() {
    setup_audit_logging
    
    trap cleanup EXIT
    
    setup_deployment
    validate_build
    
    case "${DEPLOY_TARGET}" in
        "testflight")
            deploy_testflight
            ;;
        "appstore")
            deploy_appstore
            ;;
        *)
            echo "Error: Invalid deployment target '${DEPLOY_TARGET}'"
            exit 1
            ;;
    esac
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deployment completed successfully"
}

main "$@"