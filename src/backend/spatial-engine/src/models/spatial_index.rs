use super::location::{Location, LocationError};
use metrics::{counter, gauge, histogram};
use rstar::{RTree, RTreeObject, AABB};
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::RwLock;
use tracing::{debug, error, info, instrument};

// Core constants for spatial indexing
const DEFAULT_INDEX_NODE_SIZE: usize = 16;
const MAX_POINTS_PER_QUERY: usize = 1000;
const MIN_LIDAR_RANGE_METERS: f64 = 0.5;
const MAX_LIDAR_RANGE_METERS: f64 = 50.0;
const PRECISION_AT_10M_CM: f64 = 1.0;

/// Custom error type for spatial index operations
#[derive(Debug, Error)]
pub enum SpatialIndexError {
    #[error("Location error: {0}")]
    Location(#[from] LocationError),
    #[error("Point validation error: {message}")]
    PointValidation { message: String },
    #[error("Index operation error: {message}")]
    IndexOperation { message: String },
    #[error("Query limit exceeded: {message}")]
    QueryLimit { message: String },
}

/// Represents a point in 3D space with associated metadata
#[derive(Debug, Clone)]
struct Point {
    location: Location,
    id: String,
    confidence: f64,
}

impl RTreeObject for Point {
    type Envelope = AABB<[f64; 3]>;

    fn envelope(&self) -> Self::Envelope {
        let point = self.location.to_point3().unwrap();
        AABB::from_point([point.x, point.y, point.z])
    }
}

/// Thread-safe spatial index implementation using R-tree
#[derive(Debug)]
pub struct SpatialIndex {
    rtree: Arc<RwLock<RTree<Point>>>,
    node_size: usize,
    metrics_collector: MetricsCollector,
}

/// Metrics collection for performance monitoring
struct MetricsCollector {
    prefix: String,
}

impl MetricsCollector {
    fn new(prefix: String) -> Self {
        Self { prefix }
    }

    fn record_operation(&self, operation: &str, duration: f64) {
        histogram!(
            format!("{}.{}.duration", self.prefix, operation),
            duration
        );
    }

    fn increment_counter(&self, operation: &str) {
        counter!(format!("{}.{}.count", self.prefix, operation), 1);
    }

    fn update_gauge(&self, name: &str, value: f64) {
        gauge!(format!("{}.{}", self.prefix, name), value);
    }
}

impl SpatialIndex {
    /// Creates a new thread-safe spatial index with specified configuration
    pub fn new(node_size: Option<usize>, metrics_prefix: String) -> Self {
        let node_size = node_size.unwrap_or(DEFAULT_INDEX_NODE_SIZE);
        let rtree = Arc::new(RwLock::new(RTree::new()));
        let metrics_collector = MetricsCollector::new(metrics_prefix);

        info!("Initializing spatial index with node size: {}", node_size);
        
        Self {
            rtree,
            node_size,
            metrics_collector,
        }
    }

    /// Validates spatial point against LiDAR specifications
    #[instrument(skip(point))]
    fn validate_point(point: &Point, precision_requirement: f64) -> Result<(), SpatialIndexError> {
        let point3 = point.location.to_point3().map_err(SpatialIndexError::Location)?;
        let distance_from_origin = (point3.x.powi(2) + point3.y.powi(2) + point3.z.powi(2)).sqrt();

        if !(MIN_LIDAR_RANGE_METERS..=MAX_LIDAR_RANGE_METERS).contains(&distance_from_origin) {
            return Err(SpatialIndexError::PointValidation {
                message: format!(
                    "Point distance {} outside LiDAR range [{}, {}]",
                    distance_from_origin, MIN_LIDAR_RANGE_METERS, MAX_LIDAR_RANGE_METERS
                ),
            });
        }

        if distance_from_origin <= 10.0 && precision_requirement > PRECISION_AT_10M_CM {
            return Err(SpatialIndexError::PointValidation {
                message: format!(
                    "Precision requirement {}cm exceeds LiDAR capability {}cm at 10m",
                    precision_requirement, PRECISION_AT_10M_CM
                ),
            });
        }

        Ok(())
    }

    /// Thread-safe insertion of location point into spatial index
    #[instrument(skip(self, location))]
    pub async fn insert(
        &self,
        location: Location,
        id: String,
    ) -> Result<(), SpatialIndexError> {
        let start = std::time::Instant::now();
        
        let point = Point {
            location: location.clone(),
            id,
            confidence: 1.0,
        };

        Self::validate_point(&point, PRECISION_AT_10M_CM)?;

        let mut rtree = self.rtree.write().await;
        rtree.insert(point);

        self.metrics_collector.record_operation(
            "insert",
            start.elapsed().as_secs_f64(),
        );
        self.metrics_collector.increment_counter("inserts");
        self.metrics_collector.update_gauge("size", rtree.size() as f64);

        debug!("Point inserted successfully");
        Ok(())
    }

    /// Thread-safe radius query with LiDAR precision guarantees
    #[instrument(skip(self))]
    pub async fn query_radius(
        &self,
        center: Location,
        radius_meters: f64,
    ) -> Result<Vec<(Location, String, f64)>, SpatialIndexError> {
        let start = std::time::Instant::now();

        if radius_meters > MAX_LIDAR_RANGE_METERS {
            return Err(SpatialIndexError::QueryLimit {
                message: format!(
                    "Query radius {}m exceeds LiDAR range {}m",
                    radius_meters, MAX_LIDAR_RANGE_METERS
                ),
            });
        }

        let rtree = self.rtree.read().await;
        let center_point = center.to_point3().map_err(SpatialIndexError::Location)?;
        
        let mut results = Vec::new();
        for point in rtree.locate_within_distance(
            [center_point.x, center_point.y, center_point.z],
            radius_meters.powi(2),
        ) {
            if results.len() >= MAX_POINTS_PER_QUERY {
                return Err(SpatialIndexError::QueryLimit {
                    message: format!("Query result limit {} exceeded", MAX_POINTS_PER_QUERY),
                });
            }

            let distance = point.location.calculate_distance(&center)
                .map_err(SpatialIndexError::Location)?;

            if distance <= radius_meters {
                let confidence = 1.0 - (distance / radius_meters);
                results.push((point.location.clone(), point.id.clone(), confidence));
            }
        }

        self.metrics_collector.record_operation(
            "query_radius",
            start.elapsed().as_secs_f64(),
        );
        self.metrics_collector.increment_counter("queries");
        self.metrics_collector.update_gauge("results_count", results.len() as f64);

        debug!("Radius query returned {} results", results.len());
        Ok(results)
    }

    /// Optimizes spatial index structure for improved query performance
    #[instrument(skip(self))]
    pub async fn optimize_index(&self) -> Result<OptimizationStats, SpatialIndexError> {
        let start = std::time::Instant::now();
        let mut rtree = self.rtree.write().await;
        
        let initial_size = rtree.size();
        rtree.bulk_load(rtree.iter().cloned().collect());
        let final_size = rtree.size();

        let stats = OptimizationStats {
            initial_size,
            final_size,
            duration: start.elapsed(),
        };

        self.metrics_collector.record_operation(
            "optimize",
            stats.duration.as_secs_f64(),
        );
        self.metrics_collector.update_gauge("optimization_gain", 
            (final_size as f64 - initial_size as f64) / initial_size as f64
        );

        info!("Index optimization completed: {:?}", stats);
        Ok(stats)
    }
}

/// Statistics from index optimization operations
#[derive(Debug)]
pub struct OptimizationStats {
    pub initial_size: usize,
    pub final_size: usize,
    pub duration: std::time::Duration,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_spatial_index_creation() {
        let index = SpatialIndex::new(None, "test".to_string());
        assert_eq!(index.node_size, DEFAULT_INDEX_NODE_SIZE);
    }

    #[tokio::test]
    async fn test_point_insertion() {
        let index = SpatialIndex::new(None, "test".to_string());
        let location = Location::new(37.7749, -122.4194, 10.0, 1.0, None).unwrap();
        
        assert!(index.insert(location, "test_point".to_string()).await.is_ok());
    }

    #[tokio::test]
    async fn test_radius_query() {
        let index = SpatialIndex::new(None, "test".to_string());
        let location = Location::new(37.7749, -122.4194, 10.0, 1.0, None).unwrap();
        
        index.insert(location.clone(), "test_point".to_string()).await.unwrap();
        
        let results = index.query_radius(location, 100.0).await.unwrap();
        assert!(!results.is_empty());
    }

    #[tokio::test]
    async fn test_optimization() {
        let index = SpatialIndex::new(None, "test".to_string());
        let location = Location::new(37.7749, -122.4194, 10.0, 1.0, None).unwrap();
        
        index.insert(location, "test_point".to_string()).await.unwrap();
        
        let stats = index.optimize_index().await.unwrap();
        assert_eq!(stats.initial_size, stats.final_size);
    }
}