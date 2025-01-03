//! Root module for spatial engine models providing a clean public API for spatial operations.
//! Version: 1.0.0
//! 
//! This module re-exports core spatial types and functionality for:
//! - Location management with LiDAR precision
//! - Spatial indexing for efficient proximity queries
//! - Thread-safe spatial operations with error handling

// Re-export core types from location module
pub use location::{
    Location,
    LocationError,
    haversine_distance,
};

// Re-export spatial indexing types
pub use spatial_index::{
    SpatialIndex,
    SpatialIndexError,
    OptimizationStats,
};

// Internal module declarations
mod location;
mod spatial_index;

// Constants defining spatial engine capabilities
/// Minimum supported LiDAR range in meters
pub const MIN_LIDAR_RANGE: f64 = 0.5;

/// Maximum supported LiDAR range in meters for user detection
pub const MAX_LIDAR_RANGE: f64 = 50.0;

/// Precision guarantee at 10 meters distance (in centimeters)
pub const PRECISION_AT_10M: f64 = 1.0;

/// Default confidence threshold for spatial operations
pub const DEFAULT_CONFIDENCE: f64 = 0.95;

/// Documentation and type information for core spatial operations
pub mod prelude {
    pub use super::{
        Location,
        LocationError,
        SpatialIndex,
        SpatialIndexError,
        OptimizationStats,
    };

    pub use super::{
        MIN_LIDAR_RANGE,
        MAX_LIDAR_RANGE,
        PRECISION_AT_10M,
        DEFAULT_CONFIDENCE,
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lidar_range_constants() {
        assert!(MIN_LIDAR_RANGE > 0.0);
        assert!(MAX_LIDAR_RANGE >= MIN_LIDAR_RANGE);
        assert_eq!(MAX_LIDAR_RANGE, 50.0); // Verify spec requirement
    }

    #[test]
    fn test_precision_constants() {
        assert!(PRECISION_AT_10M > 0.0);
        assert!(DEFAULT_CONFIDENCE > 0.0 && DEFAULT_CONFIDENCE <= 1.0);
    }

    #[test]
    fn test_type_reexports() {
        // Verify that core types are properly re-exported
        let _: Option<Location> = None;
        let _: Option<LocationError> = None;
        let _: Option<SpatialIndex> = None;
        let _: Option<SpatialIndexError> = None;
        let _: Option<OptimizationStats> = None;
    }
}