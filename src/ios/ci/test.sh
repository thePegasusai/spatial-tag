#!/bin/bash

# SpatialTag iOS Test Suite Runner v1.0.0
# Executes comprehensive test suite including LiDAR and AR capability validation
# Dependencies:
# - fastlane v2.212.2
# - xcpretty latest
# - bundler latest
# - slather latest

set -euo pipefail
IFS=$'\n\t'

# Global Configuration
WORKSPACE="../SpatialTag.xcworkspace"
SCHEME="SpatialTag"
DERIVED_DATA_PATH="./DerivedData"
MIN_COVERAGE=85
MIN_IOS_VERSION="15.0"
REQUIRED_DEVICE_TYPES=("iPhone12,1" "iPhone13,1" "iPhone14,1")
LIDAR_TEST_TIMEOUT=300
AR_TEST_TIMEOUT=300

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

setup_environment() {
    log "${YELLOW}Setting up test environment...${NC}"
    
    # Install dependencies
    bundle install --quiet || {
        log "${RED}Failed to install bundle dependencies${NC}"
        exit 1
    }
    
    # Verify CocoaPods installation
    if ! command -v pod &> /dev/null; then
        log "${YELLOW}Installing CocoaPods...${NC}"
        gem install cocoapods
    fi
    
    # Clean derived data
    if [ -d "$DERIVED_DATA_PATH" ]; then
        rm -rf "$DERIVED_DATA_PATH"
    fi
    mkdir -p "$DERIVED_DATA_PATH"
    
    # Verify iOS version requirement
    local device_ios_version=$(xcrun simctl list devices available -j | jq -r '.devices | .[] | .[] | select(.name | contains("iPhone")) | .runtime')
    if [[ "$device_ios_version" < "$MIN_IOS_VERSION" ]]; then
        log "${RED}Error: Minimum iOS version $MIN_IOS_VERSION required${NC}"
        exit 1
    }
    
    # Verify LiDAR-capable test devices
    local available_devices=$(xcrun simctl list devices available -j)
    local has_lidar_device=false
    for device_type in "${REQUIRED_DEVICE_TYPES[@]}"; do
        if echo "$available_devices" | jq -e --arg dt "$device_type" '.devices | .[] | .[] | select(.deviceTypeIdentifier==$dt)' > /dev/null; then
            has_lidar_device=true
            break
        fi
    done
    
    if [ "$has_lidar_device" = false ]; then
        log "${RED}Error: No LiDAR-capable test devices found${NC}"
        exit 1
    }
    
    log "${GREEN}Environment setup complete${NC}"
    return 0
}

run_unit_tests() {
    log "${YELLOW}Running unit tests...${NC}"
    
    # Run SwiftLint
    if ! bundle exec fastlane run swiftlint strict:true reporter:junit config_file:".swiftlint.yml"; then
        log "${RED}SwiftLint validation failed${NC}"
        exit 1
    }
    
    # Execute test suites
    bundle exec fastlane test \
        workspace:"$WORKSPACE" \
        scheme:"$SCHEME" \
        device:"iPhone 14 Pro" \
        clean:true \
        code_coverage:true \
        xcargs:"ONLY_ACTIVE_ARCH=YES" \
        | xcpretty --color --report junit
    
    local test_exit_code=${PIPESTATUS[0]}
    
    if [ $test_exit_code -ne 0 ]; then
        log "${RED}Unit tests failed${NC}"
        exit $test_exit_code
    fi
    
    log "${GREEN}Unit tests completed successfully${NC}"
    return 0
}

run_integration_tests() {
    log "${YELLOW}Running integration tests...${NC}"
    
    # Set up AR test environment
    export AR_TESTING=1
    export LIDAR_TESTING=1
    
    # Run integration test suite
    bundle exec fastlane scan \
        workspace:"$WORKSPACE" \
        scheme:"$SCHEME" \
        device:"iPhone 14 Pro" \
        only_testing:"ARTests" \
        clean:true \
        code_coverage:true \
        xcargs:"ONLY_ACTIVE_ARCH=YES" \
        | xcpretty --color --report junit
        
    local test_exit_code=${PIPESTATUS[0]}
    
    if [ $test_exit_code -ne 0 ]; then
        log "${RED}Integration tests failed${NC}"
        exit $test_exit_code
    }
    
    log "${GREEN}Integration tests completed successfully${NC}"
    return 0
}

generate_reports() {
    log "${YELLOW}Generating test reports...${NC}"
    
    # Generate code coverage report
    bundle exec slather coverage \
        --workspace "$WORKSPACE" \
        --scheme "$SCHEME" \
        --output-directory "$DERIVED_DATA_PATH/coverage" \
        --html \
        --show
        
    # Verify coverage threshold
    local coverage_percentage=$(grep -o "[0-9.]*%" "$DERIVED_DATA_PATH/coverage/index.html" | head -1 | cut -d. -f1)
    if [ "$coverage_percentage" -lt "$MIN_COVERAGE" ]; then
        log "${RED}Error: Code coverage ${coverage_percentage}% below minimum threshold of ${MIN_COVERAGE}%${NC}"
        exit 1
    }
    
    # Archive test artifacts
    mkdir -p "$DERIVED_DATA_PATH/reports"
    cp -R "fastlane/test_output/" "$DERIVED_DATA_PATH/reports/"
    
    log "${GREEN}Test reports generated successfully${NC}"
    return 0
}

cleanup() {
    log "${YELLOW}Cleaning up test environment...${NC}"
    
    # Archive test results
    if [ -d "$DERIVED_DATA_PATH" ]; then
        tar -czf "test-artifacts-$(date +%Y%m%d-%H%M%S).tar.gz" "$DERIVED_DATA_PATH"
    fi
    
    # Clean up derived data
    rm -rf "$DERIVED_DATA_PATH"
    
    # Reset environment variables
    unset AR_TESTING
    unset LIDAR_TESTING
    
    log "${GREEN}Cleanup completed${NC}"
    return 0
}

main() {
    local start_time=$(date +%s)
    
    # Execute test phases
    setup_environment
    run_unit_tests
    run_integration_tests
    generate_reports
    cleanup
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "${GREEN}All tests completed successfully in ${duration}s${NC}"
    exit 0
}

# Execute main function
main "$@"