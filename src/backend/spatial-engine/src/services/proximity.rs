use crate::models::location::{Location, LocationError};
use crate::models::spatial_index::{SpatialIndex, SpatialIndexError};
use crate::services::lidar::LiDARProcessor;
use tokio::sync::Mutex;
use tokio::time::Duration;
use tracing::{debug, error, info, instrument};
use thiserror::Error;
use std::sync::Arc;

// Core constants for proximity operations
const DEFAULT_DISCOVERY_RADIUS_METERS: f64 = 50.0;
const MIN_INTERACTION_DISTANCE_METERS: f64 = 0.5;
const MAX_RESULTS_PER_QUERY: usize = 100;
const LOCK_TIMEOUT_SECONDS: u64 = 5;
const MIN_CONFIDENCE_SCORE: f64 = 0.7;

/// Enhanced error type for proximity operations
#[derive(Debug, Error)]
pub enum ProximityError {
    #[error("Invalid radius: {value}m, expected between {MIN_INTERACTION_DISTANCE_METERS}m and {DEFAULT_DISCOVERY_RADIUS_METERS}m")]
    InvalidRadius { value: f64 },

    #[error("Location error: {0}")]
    Location(#[from] LocationError),

    #[error("Spatial index error: {0}")]
    SpatialIndex(#[from] SpatialIndexError),

    #[error("Lock acquisition timeout after {LOCK_TIMEOUT_SECONDS}s")]
    LockTimeout,

    #[error("Processing error: {message}")]
    Processing { message: String },
}

/// Validates discovery radius against system constraints
#[instrument]
pub fn validate_discovery_radius(radius_meters: f64) -> Result<(), ProximityError> {
    debug!("Validating discovery radius: {}m", radius_meters);

    if radius_meters < MIN_INTERACTION_DISTANCE_METERS || radius_meters > DEFAULT_DISCOVERY_RADIUS_METERS {
        error!("Invalid discovery radius: {}m", radius_meters);
        return Err(ProximityError::InvalidRadius { value: radius_meters });
    }

    debug!("Discovery radius validation successful");
    Ok(())
}

/// Thread-safe service for handling proximity-based discovery and interactions
#[derive(Debug)]
pub struct ProximityService {
    user_index: Arc<Mutex<SpatialIndex>>,
    tag_index: Arc<Mutex<SpatialIndex>>,
    lidar_processor: Arc<LiDARProcessor>,
    lock_timeout: Duration,
}

impl ProximityService {
    /// Creates new ProximityService instance with configured timeouts
    pub fn new(
        user_index: Arc<Mutex<SpatialIndex>>,
        tag_index: Arc<Mutex<SpatialIndex>>,
        lidar_processor: Arc<LiDARProcessor>,
    ) -> Self {
        info!("Initializing ProximityService");
        Self {
            user_index,
            tag_index,
            lidar_processor,
            lock_timeout: Duration::from_secs(LOCK_TIMEOUT_SECONDS),
        }
    }

    /// Discovers users within specified radius with environmental context
    #[instrument(skip(self))]
    pub async fn discover_nearby_users(
        &self,
        center: Location,
        radius_meters: Option<f64>,
    ) -> Result<Vec<(Location, String, f64)>, ProximityError> {
        let radius = radius_meters.unwrap_or(DEFAULT_DISCOVERY_RADIUS_METERS);
        validate_discovery_radius(radius)?;

        debug!("Discovering users within {}m radius", radius);

        // Query environmental context for filtering
        let env_context = self.lidar_processor.query_environment(&center, radius).await
            .map_err(|e| ProximityError::Processing { message: e.to_string() })?;

        // Get nearby users with timeout handling
        let user_index = self.user_index
            .try_lock_for(self.lock_timeout)
            .map_err(|_| ProximityError::LockTimeout)?;

        let mut nearby_users = user_index.query_radius(center.clone(), radius).await?;

        // Filter and sort results
        nearby_users.retain(|(loc, _, confidence)| {
            confidence >= &MIN_CONFIDENCE_SCORE && 
            env_context.points.iter().any(|(env_loc, _, _)| {
                loc.calculate_distance(env_loc).unwrap_or(f64::MAX) <= radius
            })
        });

        nearby_users.sort_by(|(loc1, _, conf1), (loc2, _, conf2)| {
            let dist1 = center.calculate_distance(loc1).unwrap_or(f64::MAX);
            let dist2 = center.calculate_distance(loc2).unwrap_or(f64::MAX);
            dist1.partial_cmp(&dist2)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then(conf2.partial_cmp(conf1).unwrap_or(std::cmp::Ordering::Equal))
        });

        nearby_users.truncate(MAX_RESULTS_PER_QUERY);

        info!(
            "Found {} nearby users within {}m radius",
            nearby_users.len(),
            radius
        );

        Ok(nearby_users)
    }

    /// Discovers tags within specified radius with environmental context
    #[instrument(skip(self))]
    pub async fn discover_nearby_tags(
        &self,
        center: Location,
        radius_meters: Option<f64>,
    ) -> Result<Vec<(Location, String, f64)>, ProximityError> {
        let radius = radius_meters.unwrap_or(DEFAULT_DISCOVERY_RADIUS_METERS);
        validate_discovery_radius(radius)?;

        debug!("Discovering tags within {}m radius", radius);

        // Query environmental context for filtering
        let env_context = self.lidar_processor.query_environment(&center, radius).await
            .map_err(|e| ProximityError::Processing { message: e.to_string() })?;

        // Get nearby tags with timeout handling
        let tag_index = self.tag_index
            .try_lock_for(self.lock_timeout)
            .map_err(|_| ProximityError::LockTimeout)?;

        let mut nearby_tags = tag_index.query_radius(center.clone(), radius).await?;

        // Filter and sort results
        nearby_tags.retain(|(loc, _, confidence)| {
            confidence >= &MIN_CONFIDENCE_SCORE && 
            env_context.points.iter().any(|(env_loc, _, _)| {
                loc.calculate_distance(env_loc).unwrap_or(f64::MAX) <= radius
            })
        });

        nearby_tags.sort_by(|(loc1, _, conf1), (loc2, _, conf2)| {
            let dist1 = center.calculate_distance(loc1).unwrap_or(f64::MAX);
            let dist2 = center.calculate_distance(loc2).unwrap_or(f64::MAX);
            dist1.partial_cmp(&dist2)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then(conf2.partial_cmp(conf1).unwrap_or(std::cmp::Ordering::Equal))
        });

        nearby_tags.truncate(MAX_RESULTS_PER_QUERY);

        info!(
            "Found {} nearby tags within {}m radius",
            nearby_tags.len(),
            radius
        );

        Ok(nearby_tags)
    }

    /// Checks if interaction is possible between two locations
    #[instrument(skip(self))]
    pub async fn check_interaction_possible(
        &self,
        location1: Location,
        location2: Location,
    ) -> Result<(bool, f64), ProximityError> {
        debug!("Checking interaction possibility between locations");

        let distance = location1.calculate_distance(&location2)?;
        if distance < MIN_INTERACTION_DISTANCE_METERS {
            return Ok((false, 0.0));
        }

        // Check environmental context
        let env_context = self.lidar_processor
            .query_environment(&location1, distance)
            .await
            .map_err(|e| ProximityError::Processing { message: e.to_string() })?;

        // Calculate confidence score based on environmental factors
        let confidence = env_context.points.iter()
            .filter(|(env_loc, _, _)| {
                location1.calculate_distance(env_loc).unwrap_or(f64::MAX) <= distance &&
                location2.calculate_distance(env_loc).unwrap_or(f64::MAX) <= distance
            })
            .map(|(_, _, conf)| conf)
            .fold(0.0, |acc, &x| acc.max(x));

        let interaction_possible = confidence >= MIN_CONFIDENCE_SCORE;

        debug!(
            "Interaction possibility: {}, confidence: {:.2}",
            interaction_possible,
            confidence
        );

        Ok((interaction_possible, confidence))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_validate_discovery_radius() {
        assert!(validate_discovery_radius(25.0).is_ok());
        assert!(validate_discovery_radius(0.0).is_err());
        assert!(validate_discovery_radius(100.0).is_err());
    }

    // Additional tests would be implemented here
}