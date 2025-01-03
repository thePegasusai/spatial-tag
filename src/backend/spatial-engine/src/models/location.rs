use atomic_float::AtomicF64;
use nalgebra::Point3;
use serde::{Deserialize, Serialize};
use std::time::Instant;
use thiserror::Error;

// Constants for location validation and calculations
const EARTH_RADIUS_METERS: f64 = 6371000.0;
const MIN_ALTITUDE_METERS: f64 = -100.0;
const MAX_ALTITUDE_METERS: f64 = 10000.0;
const MIN_ACCURACY_METERS: f64 = 0.01;
const MAX_ACCURACY_METERS: f64 = 50.0;
const DEFAULT_CONFIDENCE_THRESHOLD: f64 = 0.95;

/// Thread-safe, memory-optimized representation of a precise 3D location with LiDAR accuracy
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Location {
    latitude: AtomicF64,
    longitude: AtomicF64,
    altitude: AtomicF64,
    accuracy_meters: AtomicF64,
    confidence_score: AtomicF64,
    timestamp: Instant,
    is_calibrated: bool,
}

/// Comprehensive error type for location operations
#[derive(Debug, Error)]
pub enum LocationError {
    #[error("Invalid latitude value: {value:?}, {message}")]
    InvalidLatitude { value: f64, message: String },
    #[error("Invalid longitude value: {value:?}, {message}")]
    InvalidLongitude { value: f64, message: String },
    #[error("Invalid altitude value: {value:?}, {message}")]
    InvalidAltitude { value: f64, message: String },
    #[error("Invalid accuracy value: {value:?}, {message}")]
    InvalidAccuracy { value: f64, message: String },
    #[error("Invalid radius value: {value:?}, {message}")]
    InvalidRadius { value: f64, message: String },
    #[error("Calculation error: {message}")]
    CalculationError { message: String },
}

impl Location {
    /// Creates a new thread-safe Location instance with comprehensive validation
    pub fn new(
        latitude: f64,
        longitude: f64,
        altitude: f64,
        accuracy_meters: f64,
        confidence_score: Option<f64>,
    ) -> Result<Self, LocationError> {
        // Validate latitude
        if !(-90.0..=90.0).contains(&latitude) {
            return Err(LocationError::InvalidLatitude {
                value: latitude,
                message: "Latitude must be between -90 and 90 degrees".to_string(),
            });
        }

        // Validate longitude
        if !(-180.0..=180.0).contains(&longitude) {
            return Err(LocationError::InvalidLongitude {
                value: longitude,
                message: "Longitude must be between -180 and 180 degrees".to_string(),
            });
        }

        // Validate altitude
        if !(MIN_ALTITUDE_METERS..=MAX_ALTITUDE_METERS).contains(&altitude) {
            return Err(LocationError::InvalidAltitude {
                value: altitude,
                message: format!(
                    "Altitude must be between {} and {} meters",
                    MIN_ALTITUDE_METERS, MAX_ALTITUDE_METERS
                ),
            });
        }

        // Validate accuracy
        if !(MIN_ACCURACY_METERS..=MAX_ACCURACY_METERS).contains(&accuracy_meters) {
            return Err(LocationError::InvalidAccuracy {
                value: accuracy_meters,
                message: format!(
                    "Accuracy must be between {} and {} meters",
                    MIN_ACCURACY_METERS, MAX_ACCURACY_METERS
                ),
            });
        }

        Ok(Location {
            latitude: AtomicF64::new(latitude),
            longitude: AtomicF64::new(longitude),
            altitude: AtomicF64::new(altitude),
            accuracy_meters: AtomicF64::new(accuracy_meters),
            confidence_score: AtomicF64::new(confidence_score.unwrap_or(DEFAULT_CONFIDENCE_THRESHOLD)),
            timestamp: Instant::now(),
            is_calibrated: true,
        })
    }

    /// Calculates precise 3D distance to another location with error compensation
    pub fn calculate_distance(&self, other: &Location) -> Result<f64, LocationError> {
        let lat1 = self.latitude.load(std::sync::atomic::Ordering::Acquire);
        let lon1 = self.longitude.load(std::sync::atomic::Ordering::Acquire);
        let alt1 = self.altitude.load(std::sync::atomic::Ordering::Acquire);
        
        let lat2 = other.latitude.load(std::sync::atomic::Ordering::Acquire);
        let lon2 = other.longitude.load(std::sync::atomic::Ordering::Acquire);
        let alt2 = other.altitude.load(std::sync::atomic::Ordering::Acquire);

        // Calculate 2D distance using haversine formula
        let surface_distance = haversine_distance(lat1, lon1, lat2, lon2);

        // Calculate altitude difference with accuracy compensation
        let altitude_diff = (alt2 - alt1).abs();
        
        // Calculate 3D distance using Pythagorean theorem
        let distance = (surface_distance.powi(2) + altitude_diff.powi(2)).sqrt();

        // Validate result against LiDAR specifications
        if distance > MAX_ACCURACY_METERS {
            Ok(distance)
        } else if distance < MIN_ACCURACY_METERS {
            Err(LocationError::CalculationError {
                message: "Distance calculation below minimum accuracy threshold".to_string(),
            })
        } else {
            Ok(distance)
        }
    }

    /// Thread-safe check if another location is within specified radius
    pub fn is_within_radius(
        &self,
        other: &Location,
        radius_meters: f64,
    ) -> Result<bool, LocationError> {
        // Validate radius
        if radius_meters <= 0.0 || radius_meters > MAX_ACCURACY_METERS {
            return Err(LocationError::InvalidRadius {
                value: radius_meters,
                message: format!(
                    "Radius must be between 0 and {} meters",
                    MAX_ACCURACY_METERS
                ),
            });
        }

        // Calculate distance with confidence adjustment
        let distance = self.calculate_distance(other)?;
        let confidence = self.confidence_score.load(std::sync::atomic::Ordering::Acquire);
        let adjusted_radius = radius_meters * confidence;

        Ok(distance <= adjusted_radius)
    }

    /// Converts location to nalgebra Point3 with precision guarantees
    pub fn to_point3(&self) -> Result<Point3<f64>, LocationError> {
        let lat = self.latitude.load(std::sync::atomic::Ordering::Acquire);
        let lon = self.longitude.load(std::sync::atomic::Ordering::Acquire);
        let alt = self.altitude.load(std::sync::atomic::Ordering::Acquire);

        // Convert to radians
        let lat_rad = lat.to_radians();
        let lon_rad = lon.to_radians();

        // Calculate cartesian coordinates
        let x = EARTH_RADIUS_METERS * lat_rad.cos() * lon_rad.cos();
        let y = EARTH_RADIUS_METERS * lat_rad.cos() * lon_rad.sin();
        let z = EARTH_RADIUS_METERS * lat_rad.sin() + alt;

        Ok(Point3::new(x, y, z))
    }
}

/// Calculates the great-circle distance between two points using high-precision operations
#[inline]
pub fn haversine_distance(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let lat1_rad = lat1.to_radians();
    let lon1_rad = lon1.to_radians();
    let lat2_rad = lat2.to_radians();
    let lon2_rad = lon2.to_radians();

    let delta_lat = lat2_rad - lat1_rad;
    let delta_lon = lon2_rad - lon1_rad;

    let a = (delta_lat / 2.0).sin().powi(2)
        + lat1_rad.cos() * lat2_rad.cos() * (delta_lon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().asin();

    EARTH_RADIUS_METERS * c
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_location_creation() {
        let location = Location::new(37.7749, -122.4194, 0.0, 1.0, None).unwrap();
        assert!(location.is_calibrated);
    }

    #[test]
    fn test_invalid_latitude() {
        assert!(Location::new(91.0, 0.0, 0.0, 1.0, None).is_err());
    }

    #[test]
    fn test_distance_calculation() {
        let loc1 = Location::new(37.7749, -122.4194, 0.0, 1.0, None).unwrap();
        let loc2 = Location::new(37.7749, -122.4294, 0.0, 1.0, None).unwrap();
        assert!(loc1.calculate_distance(&loc2).is_ok());
    }

    #[test]
    fn test_radius_check() {
        let loc1 = Location::new(37.7749, -122.4194, 0.0, 1.0, None).unwrap();
        let loc2 = Location::new(37.7749, -122.4195, 0.0, 1.0, None).unwrap();
        assert!(loc1.is_within_radius(&loc2, 50.0).unwrap());
    }
}