//! gRPC server module for high-performance spatial data processing
//! Version: tonic 0.9
//! Version: prost 0.11

use tonic::{include_proto, transport::Server};
use prost::Message;

// Re-export server module
pub mod server;
pub use server::{SpatialServiceServer, ServerConfig, run_server};

// Protocol buffer package name
const PROTO_PACKAGE: &str = "spatial.v1";

/// Protocol buffer generated types for spatial data processing
pub mod proto {
    use super::*;

    // Location representation with LiDAR precision
    #[derive(Clone, PartialEq, Message)]
    pub struct Location {
        #[prost(double, tag = "1")]
        pub latitude: f64,
        #[prost(double, tag = "2")]
        pub longitude: f64,
        #[prost(double, tag = "3")]
        pub altitude: f64,
        #[prost(double, tag = "4")]
        pub accuracy_meters: f64,
        #[prost(double, tag = "5")]
        pub confidence_score: f64,
    }

    // 3D spatial point with coordinates
    #[derive(Clone, PartialEq, Message)]
    pub struct SpatialPoint {
        #[prost(double, tag = "1")]
        pub x: f64,
        #[prost(double, tag = "2")]
        pub y: f64,
        #[prost(double, tag = "3")]
        pub z: f64,
    }

    // Proximity query request
    #[derive(Clone, PartialEq, Message)]
    pub struct ProximityRequest {
        #[prost(message, required, tag = "1")]
        pub location: Location,
        #[prost(double, tag = "2")]
        pub radius_meters: f64,
        #[prost(bool, tag = "3")]
        pub include_environment: bool,
    }

    // Proximity query response
    #[derive(Clone, PartialEq, Message)]
    pub struct ProximityResponse {
        #[prost(message, repeated, tag = "1")]
        pub nearby_points: Vec<SpatialPoint>,
        #[prost(double, tag = "2")]
        pub processing_time_ms: f64,
        #[prost(double, tag = "3")]
        pub confidence_score: f64,
    }

    // LiDAR scan data
    #[derive(Clone, PartialEq, Message)]
    pub struct LiDARScan {
        #[prost(message, repeated, tag = "1")]
        pub points: Vec<SpatialPoint>,
        #[prost(enumeration = "ScanQuality", tag = "2")]
        pub quality: i32,
        #[prost(double, tag = "3")]
        pub scan_time_ms: f64,
    }

    // LiDAR scan quality levels
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, enumeration)]
    pub enum ScanQuality {
        Low = 0,
        Medium = 1,
        High = 2,
    }

    // Environmental map from LiDAR data
    #[derive(Clone, PartialEq, Message)]
    pub struct EnvironmentMap {
        #[prost(message, repeated, tag = "1")]
        pub points: Vec<SpatialPoint>,
        #[prost(double, tag = "2")]
        pub processing_time_ms: f64,
        #[prost(double, tag = "3")]
        pub confidence_threshold: f64,
        #[prost(string, tag = "4")]
        pub map_id: String,
    }

    // Performance metrics for monitoring
    #[derive(Clone, PartialEq, Message)]
    pub struct SpatialMetrics {
        #[prost(uint64, tag = "1")]
        pub points_processed: u64,
        #[prost(double, tag = "2")]
        pub average_processing_time_ms: f64,
        #[prost(double, tag = "3")]
        pub confidence_score: f64,
        #[prost(uint32, tag = "4")]
        pub active_connections: u32,
    }

    // Health check for service monitoring
    #[derive(Clone, PartialEq, Message)]
    pub struct HealthCheck {
        #[prost(bool, tag = "1")]
        pub is_healthy: bool,
        #[prost(string, tag = "2")]
        pub status_message: String,
        #[prost(double, tag = "3")]
        pub uptime_seconds: f64,
    }
}

// Implement conversion traits for internal types
impl From<crate::models::location::Location> for proto::Location {
    fn from(loc: crate::models::location::Location) -> Self {
        Self {
            latitude: loc.latitude.load(std::sync::atomic::Ordering::Acquire),
            longitude: loc.longitude.load(std::sync::atomic::Ordering::Acquire),
            altitude: loc.altitude.load(std::sync::atomic::Ordering::Acquire),
            accuracy_meters: loc.accuracy_meters.load(std::sync::atomic::Ordering::Acquire),
            confidence_score: loc.confidence_score.load(std::sync::atomic::Ordering::Acquire),
        }
    }
}

impl TryFrom<proto::Location> for crate::models::location::Location {
    type Error = crate::models::location::LocationError;

    fn try_from(proto: proto::Location) -> Result<Self, Self::Error> {
        crate::models::location::Location::new(
            proto.latitude,
            proto.longitude,
            proto.altitude,
            proto.accuracy_meters,
            Some(proto.confidence_score),
        )
    }
}

// Generate gRPC service definitions
tonic::include_proto!("spatial.v1");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_location_conversion() {
        let internal_loc = crate::models::location::Location::new(
            37.7749,
            -122.4194,
            10.0,
            1.0,
            Some(0.95),
        ).unwrap();
        
        let proto_loc: proto::Location = internal_loc.clone().into();
        assert_eq!(proto_loc.latitude, 37.7749);
        assert_eq!(proto_loc.longitude, -122.4194);
        
        let converted_loc = crate::models::location::Location::try_from(proto_loc).unwrap();
        assert!(converted_loc.calculate_distance(&internal_loc).unwrap() < 0.01);
    }
}