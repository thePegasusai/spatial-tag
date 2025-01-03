//! Services module for the Spatial Tag Engine
//! 
//! Provides core LiDAR processing and proximity detection functionality with comprehensive
//! environment mapping capabilities within a 50-meter radius. Implements high-precision
//! spatial awareness and real-time discovery features.
//!
//! Version: 1.0.0

#![deny(missing_docs)]
#![deny(unsafe_code)]

use tracing::{debug, error, info, instrument};

// Re-export core service modules with their public interfaces
pub mod lidar;
pub mod proximity;

// Re-export key types from service modules for convenient access
pub use lidar::{
    LiDARProcessor,
    LiDARError,
    LiDARConfig,
    validate_scan_range,
    process_point_cloud,
    calibrate_lidar,
};

pub use proximity::{
    ProximityService,
    ProximityError,
    ProximityConfig,
    validate_discovery_radius,
    detect_nearby_users,
    calculate_spatial_density,
};

// Core constants derived from technical specifications
/// Minimum scanning range in meters for LiDAR operations
pub const MIN_SCAN_RANGE: f64 = 0.5;

/// Maximum scanning range in meters for LiDAR operations
pub const MAX_SCAN_RANGE: f64 = 50.0;

/// Required precision at 10 meters distance (±1cm)
pub const PRECISION_AT_10M: f64 = 0.01;

/// Horizontal field of view in degrees
pub const HORIZONTAL_FOV: f64 = 120.0;

/// Minimum refresh rate in Hz for real-time processing
pub const MIN_REFRESH_RATE: u32 = 30;

/// Default confidence threshold for spatial operations
pub const DEFAULT_CONFIDENCE: f64 = 0.85;

/// Service initialization and configuration functions
#[instrument]
pub fn init_spatial_services() -> Result<(), String> {
    info!("Initializing Spatial Tag Engine services");
    debug!("Configuring LiDAR parameters: range={}-{}m, FOV={}°", 
           MIN_SCAN_RANGE, MAX_SCAN_RANGE, HORIZONTAL_FOV);
    
    // Validate core requirements
    if MIN_SCAN_RANGE < 0.5 || MAX_SCAN_RANGE > 50.0 {
        error!("Invalid scan range configuration");
        return Err("Scan range must be between 0.5m and 50.0m".to_string());
    }

    if HORIZONTAL_FOV != 120.0 {
        error!("Invalid FOV configuration");
        return Err("Horizontal FOV must be 120 degrees".to_string());
    }

    if MIN_REFRESH_RATE < 30 {
        error!("Invalid refresh rate configuration");
        return Err("Minimum refresh rate must be 30Hz".to_string());
    }

    info!("Spatial Tag Engine services initialized successfully");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_service_initialization() {
        assert!(init_spatial_services().is_ok());
    }

    #[test]
    fn test_core_constants() {
        assert_eq!(MIN_SCAN_RANGE, 0.5);
        assert_eq!(MAX_SCAN_RANGE, 50.0);
        assert_eq!(HORIZONTAL_FOV, 120.0);
        assert_eq!(MIN_REFRESH_RATE, 30);
    }
}