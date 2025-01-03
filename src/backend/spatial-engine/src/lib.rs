//! Spatial Engine root library providing high-performance LiDAR-based spatial processing
//! with comprehensive monitoring, error handling, and graceful degradation capabilities.
//! 
//! Version: 0.1.0

use anyhow::{Context, Result};
use metrics::{counter, gauge, histogram};
use tokio::sync::Mutex;
use tracing::{debug, error, info, instrument, warn};

use std::sync::Arc;
use std::time::{Duration, Instant};

// Internal module imports with enhanced thread safety
use crate::models::{Location, SpatialIndex, ProcessedScan};
use crate::services::{LiDARProcessor, ProximityService, HealthCheck};

// Core constants for engine configuration
const VERSION: &str = "0.1.0";
const MAX_PROCESSING_TIME_MS: u64 = 100;
const MIN_BATTERY_LEVEL: u8 = 15;
const GRACEFUL_SHUTDOWN_TIMEOUT_MS: u64 = 5000;

/// Enhanced configuration for the Spatial Engine
#[derive(Debug, Clone)]
pub struct Settings {
    scan_range_meters: f64,
    confidence_threshold: f64,
    refresh_rate_hz: u32,
    batch_size: usize,
    metrics_prefix: String,
    graceful_shutdown_timeout: Duration,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            scan_range_meters: 50.0,
            confidence_threshold: 0.95,
            refresh_rate_hz: 30,
            batch_size: 1024,
            metrics_prefix: "spatial_engine".to_string(),
            graceful_shutdown_timeout: Duration::from_millis(GRACEFUL_SHUTDOWN_TIMEOUT_MS),
        }
    }
}

/// Core engine struct with comprehensive monitoring and graceful degradation
#[derive(Debug)]
pub struct SpatialEngine {
    lidar_processor: Arc<Mutex<LiDARProcessor>>,
    proximity_service: Arc<ProximityService>,
    spatial_index: Arc<Mutex<SpatialIndex>>,
    settings: Settings,
    health_monitor: HealthMonitor,
    metrics_collector: MetricsCollector,
}

/// Health monitoring for system components
#[derive(Debug)]
struct HealthMonitor {
    last_health_check: Arc<Mutex<Instant>>,
    battery_level: Arc<Mutex<u8>>,
    processing_time_ms: Arc<Mutex<u64>>,
}

/// Performance metrics collection
#[derive(Debug)]
struct MetricsCollector {
    prefix: String,
}

impl MetricsCollector {
    fn new(prefix: String) -> Self {
        Self { prefix }
    }

    fn record_operation(&self, operation: &str, duration: f64) {
        histogram!(
            format!("{}.{}.duration_ms", self.prefix, operation),
            duration
        );
    }

    fn increment_counter(&self, name: &str) {
        counter!(format!("{}.{}", self.prefix, name), 1);
    }

    fn update_gauge(&self, name: &str, value: f64) {
        gauge!(format!("{}.{}", self.prefix, name), value);
    }
}

impl SpatialEngine {
    /// Creates new SpatialEngine instance with enhanced initialization
    #[instrument(skip(config), err)]
    pub async fn new(config: Settings) -> Result<Self> {
        info!("Initializing Spatial Engine v{}", VERSION);
        
        // Initialize spatial index with monitoring
        let spatial_index = Arc::new(Mutex::new(SpatialIndex::new(
            None,
            format!("{}.spatial_index", config.metrics_prefix),
        )));

        // Initialize LiDAR processor with error handling
        let lidar_processor = Arc::new(Mutex::new(LiDARProcessor::new(
            spatial_index.clone(),
            Some(config.scan_range_meters),
            Some(config.confidence_threshold),
            None,
        ).context("Failed to initialize LiDAR processor")?));

        // Initialize proximity service with health checks
        let proximity_service = Arc::new(ProximityService::new(
            spatial_index.clone(),
            spatial_index.clone(),
            lidar_processor.clone(),
        ));

        // Initialize monitoring components
        let health_monitor = HealthMonitor {
            last_health_check: Arc::new(Mutex::new(Instant::now())),
            battery_level: Arc::new(Mutex::new(100)),
            processing_time_ms: Arc::new(Mutex::new(0)),
        };

        let metrics_collector = MetricsCollector::new(config.metrics_prefix.clone());

        let engine = Self {
            lidar_processor,
            proximity_service,
            spatial_index,
            settings: config,
            health_monitor,
            metrics_collector,
        };

        info!("Spatial Engine initialization completed successfully");
        Ok(engine)
    }

    /// Processes LiDAR scan with comprehensive error handling and monitoring
    #[instrument(skip(self, scan_data), err)]
    pub async fn process_scan(&self, scan_data: ProcessedScan) -> Result<()> {
        let start_time = Instant::now();
        debug!("Processing LiDAR scan");

        // Check system health before processing
        self.check_health().await?;

        // Process scan with error handling
        let processor = self.lidar_processor.lock().await;
        let result = processor
            .process_point_cloud(scan_data.points)
            .await
            .context("Failed to process point cloud")?;

        // Update metrics
        let processing_time = start_time.elapsed().as_secs_f64() * 1000.0;
        self.metrics_collector.record_operation("scan_processing", processing_time);
        self.metrics_collector.update_gauge("points_processed", result.points.len() as f64);

        // Check processing time constraints
        if processing_time > MAX_PROCESSING_TIME_MS as f64 {
            warn!(
                "Processing time ({:.2}ms) exceeded threshold of {}ms",
                processing_time, MAX_PROCESSING_TIME_MS
            );
        }

        debug!("Scan processing completed in {:.2}ms", processing_time);
        Ok(())
    }

    /// Discovers nearby users with environmental context
    #[instrument(skip(self))]
    pub async fn discover_nearby_users(
        &self,
        location: Location,
        radius_meters: Option<f64>,
    ) -> Result<Vec<(Location, String, f64)>> {
        let start_time = Instant::now();
        debug!("Discovering nearby users");

        // Check system health
        self.check_health().await?;

        // Perform discovery with error handling
        let nearby_users = self.proximity_service
            .discover_nearby_users(location, radius_meters)
            .await
            .context("Failed to discover nearby users")?;

        // Update metrics
        let processing_time = start_time.elapsed().as_secs_f64() * 1000.0;
        self.metrics_collector.record_operation("user_discovery", processing_time);
        self.metrics_collector.update_gauge("nearby_users_count", nearby_users.len() as f64);

        debug!("User discovery completed in {:.2}ms", processing_time);
        Ok(nearby_users)
    }

    /// Performs comprehensive health check of system components
    #[instrument(skip(self))]
    async fn check_health(&self) -> Result<()> {
        let mut health_check = self.health_monitor.last_health_check.lock().await;
        let battery_level = *self.health_monitor.battery_level.lock().await;

        // Check battery level for graceful degradation
        if battery_level < MIN_BATTERY_LEVEL {
            error!("Battery level critical: {}%", battery_level);
            return Err(anyhow::anyhow!("Battery level too low for operation"));
        }

        // Update health check timestamp
        *health_check = Instant::now();
        
        Ok(())
    }

    /// Initiates graceful shutdown of system components
    #[instrument(skip(self))]
    pub async fn shutdown(&self) -> Result<()> {
        info!("Initiating graceful shutdown");
        let start_time = Instant::now();

        // Flush metrics
        self.metrics_collector.update_gauge("shutdown_initiated", 1.0);

        // Wait for pending operations to complete
        tokio::time::sleep(self.settings.graceful_shutdown_timeout).await;

        let shutdown_time = start_time.elapsed().as_secs_f64() * 1000.0;
        info!("Shutdown completed in {:.2}ms", shutdown_time);
        
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_engine_initialization() {
        let config = Settings::default();
        let engine = SpatialEngine::new(config).await;
        assert!(engine.is_ok());
    }

    #[tokio::test]
    async fn test_health_check() {
        let engine = SpatialEngine::new(Settings::default()).await.unwrap();
        assert!(engine.check_health().await.is_ok());
    }

    #[tokio::test]
    async fn test_graceful_shutdown() {
        let engine = SpatialEngine::new(Settings::default()).await.unwrap();
        assert!(engine.shutdown().await.is_ok());
    }
}