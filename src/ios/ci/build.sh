#!/bin/bash

# Spatial Tag iOS Build Script
# Version: 1.0.0
# Requires: Xcode 14.0+, iOS 15.0+, LiDAR capability

set -euo pipefail
IFS=$'\n\t'

# Configuration
WORKSPACE_PATH="../SpatialTag.xcworkspace"
SCHEME_NAME="SpatialTag"
CONFIGURATION="Release"
DERIVED_DATA_PATH="./DerivedData"
ARCHIVE_PATH="./build/SpatialTag.xcarchive"
MIN_IOS_VERSION="15.0"
REQUIRED_DEVICE_CAPABILITIES=("arm64" "lidar")
SECURITY_SCAN_ENABLED=true
BUILD_TIMEOUT=3600

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Error handling
handle_error() {
    log "Error on line $1" "$RED"
    exit 1
}

trap 'handle_error $LINENO' ERR

validate_environment() {
    log "Validating build environment..." "$YELLOW"
    
    # Check Xcode version
    if ! xcodebuild -version | grep -q "Xcode 14"; then
        log "Error: Xcode 14.0 or higher is required" "$RED"
        exit 1
    }
    
    # Verify required tools
    local required_tools=("fastlane" "cocoapods" "xcpretty" "sonar-scanner")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "Error: $tool is not installed" "$RED"
            exit 1
        fi
    done
    
    # Verify LiDAR SDK availability
    if ! xcodebuild -showsdks | grep -q "iOS"; then
        log "Error: iOS SDK not found" "$RED"
        exit 1
    }
    
    log "Environment validation successful" "$GREEN"
}

setup_security() {
    log "Setting up security measures..." "$YELLOW"
    
    # Initialize keychain for CI environment
    if [[ "${CI:-}" == "true" ]]; then
        security create-keychain -p "" build.keychain
        security default-keychain -s build.keychain
        security unlock-keychain -p "" build.keychain
        security set-keychain-settings -t 3600 -l build.keychain
    fi
    
    # Setup code signing
    if ! fastlane run setup_ci; then
        log "Error: Failed to setup CI environment" "$RED"
        exit 1
    fi
    
    # Configure code signing using match
    if ! fastlane match development --readonly true; then
        log "Error: Failed to setup code signing" "$RED"
        exit 1
    }
    
    log "Security setup completed" "$GREEN"
}

build_app() {
    log "Starting build process..." "$YELLOW"
    
    # Clean build directory
    if [[ -d "$DERIVED_DATA_PATH" ]]; then
        rm -rf "$DERIVED_DATA_PATH"
    fi
    
    # Install dependencies
    log "Installing dependencies..."
    if ! bundle exec pod install --repo-update; then
        log "Error: CocoaPods installation failed" "$RED"
        exit 1
    }
    
    # Security scan of dependencies
    if [[ "$SECURITY_SCAN_ENABLED" == true ]]; then
        log "Running security scan..."
        if ! bundle exec fastlane run audit_pods verbose:true; then
            log "Error: Security scan failed" "$RED"
            exit 1
        fi
    fi
    
    # Build the application
    log "Building application..."
    if ! bundle exec fastlane build \
        workspace:"$WORKSPACE_PATH" \
        scheme:"$SCHEME_NAME" \
        configuration:"$CONFIGURATION" \
        clean:true \
        derived_data_path:"$DERIVED_DATA_PATH" \
        archive_path:"$ARCHIVE_PATH" \
        | xcpretty; then
        log "Error: Build failed" "$RED"
        exit 1
    fi
    
    log "Build completed successfully" "$GREEN"
}

verify_artifacts() {
    log "Verifying build artifacts..." "$YELLOW"
    
    # Check archive existence
    if [[ ! -d "$ARCHIVE_PATH" ]]; then
        log "Error: Archive not found at $ARCHIVE_PATH" "$RED"
        exit 1
    }
    
    # Verify code signature
    if ! codesign -vv "$ARCHIVE_PATH/Products/Applications/SpatialTag.app" 2>&1; then
        log "Error: Code signature verification failed" "$RED"
        exit 1
    }
    
    # Verify LiDAR capability
    local info_plist="$ARCHIVE_PATH/Products/Applications/SpatialTag.app/Info.plist"
    if ! /usr/libexec/PlistBuddy -c "Print :UIRequiredDeviceCapabilities" "$info_plist" | grep -q "lidar"; then
        log "Error: LiDAR capability not found in Info.plist" "$RED"
        exit 1
    }
    
    # Run SonarQube analysis
    if [[ "$SECURITY_SCAN_ENABLED" == true ]]; then
        log "Running SonarQube analysis..."
        if ! sonar-scanner \
            -Dsonar.projectKey=SpatialTag-iOS \
            -Dsonar.sources=. \
            -Dsonar.swift.coverage.reportPaths=fastlane/test_output/coverage.xml; then
            log "Warning: SonarQube analysis failed" "$YELLOW"
        fi
    fi
    
    log "Artifact verification completed" "$GREEN"
}

# Main execution
main() {
    log "Starting iOS build pipeline..." "$YELLOW"
    
    # Execute build stages
    validate_environment
    setup_security
    build_app
    verify_artifacts
    
    log "Build pipeline completed successfully" "$GREEN"
    exit 0
}

# Execute main with timeout
timeout "$BUILD_TIMEOUT" bash -c main || {
    log "Error: Build timed out after ${BUILD_TIMEOUT} seconds" "$RED"
    exit 1
}