use crate::services::lidar::{LiDARProcessor, LiDARError};
use crate::services::proximity::{ProximityService, ProximityError};
use governor::{Quota, RateLimiter};
use metrics::{counter, gauge, histogram};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tokio::sync::Mutex;
use tonic::{Request, Response, Status, transport::Server};
use tracing::{debug, error, info, instrument};
use nonzero_ext::nonzero;

// Server configuration constants from technical specifications
const DEFAULT_SERVER_PORT: u16 = 50051;
const MAX_CONCURRENT_REQUESTS: u32 = 1000;
const REQUEST_TIMEOUT_MS: u64 = 100;
const MAX_REQUESTS_PER_MINUTE: u32 = 600;
const GRACEFUL_SHUTDOWN_SECONDS: u64 = 30;
const HEALTH_CHECK_INTERVAL_MS: u64 = 5000;

/// Enhanced error type for server operations
#[derive(Debug, Error)]
pub enum ServerError {
    #[error("Transport error: {0}")]
    Transport(#[from] tonic::transport::Error),

    #[error("LiDAR processing error: {0}")]
    LiDAR(#[from] LiDARError),

    #[error("Proximity error: {0}")]
    Proximity(#[from] ProximityError),

    #[error("Rate limit exceeded: {message}")]
    RateLimit { message: String },

    #[error("Server configuration error: {message}")]
    Configuration { message: String },
}

/// Server configuration with production settings
#[derive(Debug, Clone)]
pub struct ServerConfig {
    port: u16,
    max_concurrent_requests: u32,
    request_timeout: Duration,
    rate_limit_per_minute: u32,
    graceful_shutdown_timeout: Duration,
    health_check_interval: Duration,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            port: DEFAULT_SERVER_PORT,
            max_concurrent_requests: MAX_CONCURRENT_REQUESTS,
            request_timeout: Duration::from_millis(REQUEST_TIMEOUT_MS),
            rate_limit_per_minute: MAX_REQUESTS_PER_MINUTE,
            graceful_shutdown_timeout: Duration::from_secs(GRACEFUL_SHUTDOWN_SECONDS),
            health_check_interval: Duration::from_millis(HEALTH_CHECK_INTERVAL_MS),
        }
    }
}

/// Production-ready gRPC server implementation
#[derive(Debug)]
pub struct SpatialServiceServer {
    lidar_processor: Arc<LiDARProcessor>,
    proximity_service: Arc<ProximityService>,
    rate_limiter: Arc<RateLimiter>,
    config: ServerConfig,
    metrics: Arc<Mutex<MetricsCollector>>,
}

/// Metrics collection for monitoring
#[derive(Debug)]
struct MetricsCollector {
    requests_total: u64,
    active_connections: u32,
    processing_times_ms: Vec<f64>,
}

impl SpatialServiceServer {
    /// Creates new server instance with production configuration
    pub fn new(
        lidar_processor: Arc<LiDARProcessor>,
        proximity_service: Arc<ProximityService>,
        config: Option<ServerConfig>,
    ) -> Self {
        let config = config.unwrap_or_default();
        
        let rate_limiter = Arc::new(RateLimiter::direct(Quota::per_minute(
            nonzero!(config.rate_limit_per_minute),
        )));

        let metrics = Arc::new(Mutex::new(MetricsCollector {
            requests_total: 0,
            active_connections: 0,
            processing_times_ms: Vec::new(),
        }));

        info!("Initializing SpatialServiceServer with config: {:?}", config);
        
        Self {
            lidar_processor,
            proximity_service,
            rate_limiter,
            config,
            metrics,
        }
    }

    /// Processes LiDAR scan with comprehensive monitoring
    #[instrument(skip(self, request))]
    async fn process_lidar_scan(
        &self,
        request: Request<LiDARScanRequest>,
    ) -> Result<Response<LiDARScanResponse>, Status> {
        let start_time = std::time::Instant::now();
        
        // Rate limiting check
        if !self.rate_limiter.check().is_ok() {
            error!("Rate limit exceeded for LiDAR scan processing");
            return Err(Status::resource_exhausted("Rate limit exceeded"));
        }

        // Update metrics
        let mut metrics = self.metrics.lock().await;
        metrics.requests_total += 1;
        metrics.active_connections += 1;
        
        // Process request with timeout
        let scan_result = tokio::time::timeout(
            self.config.request_timeout,
            self.lidar_processor.process_point_cloud(request.into_inner().points),
        ).await.map_err(|_| Status::deadline_exceeded("Request timeout"))?;

        match scan_result {
            Ok(environment_map) => {
                let processing_time = start_time.elapsed().as_secs_f64() * 1000.0;
                metrics.processing_times_ms.push(processing_time);
                metrics.active_connections -= 1;

                // Record metrics
                histogram!("lidar.scan.duration_ms", processing_time);
                counter!("lidar.scan.success", 1);
                gauge!("lidar.active_connections", metrics.active_connections as f64);

                debug!("LiDAR scan processed successfully in {:.2}ms", processing_time);
                
                Ok(Response::new(LiDARScanResponse {
                    environment_map: Some(environment_map.into()),
                    processing_time_ms: processing_time,
                }))
            },
            Err(e) => {
                error!("LiDAR scan processing error: {:?}", e);
                counter!("lidar.scan.error", 1);
                Err(Status::internal(format!("Processing error: {}", e)))
            }
        }
    }

    /// Handles proximity queries with performance optimization
    #[instrument(skip(self, request))]
    async fn get_nearby_points(
        &self,
        request: Request<ProximityRequest>,
    ) -> Result<Response<ProximityResponse>, Status> {
        let start_time = std::time::Instant::now();

        // Rate limiting check
        if !self.rate_limiter.check().is_ok() {
            error!("Rate limit exceeded for proximity query");
            return Err(Status::resource_exhausted("Rate limit exceeded"));
        }

        // Update metrics
        let mut metrics = self.metrics.lock().await;
        metrics.requests_total += 1;
        metrics.active_connections += 1;

        // Process request with timeout
        let proximity_result = tokio::time::timeout(
            self.config.request_timeout,
            self.proximity_service.discover_nearby_points(
                request.into_inner().location,
                request.into_inner().radius_meters,
            ),
        ).await.map_err(|_| Status::deadline_exceeded("Request timeout"))?;

        match proximity_result {
            Ok(nearby_points) => {
                let processing_time = start_time.elapsed().as_secs_f64() * 1000.0;
                metrics.processing_times_ms.push(processing_time);
                metrics.active_connections -= 1;

                // Record metrics
                histogram!("proximity.query.duration_ms", processing_time);
                counter!("proximity.query.success", 1);
                gauge!("proximity.active_connections", metrics.active_connections as f64);

                debug!("Proximity query completed successfully in {:.2}ms", processing_time);
                
                Ok(Response::new(ProximityResponse {
                    points: nearby_points.into_iter().map(Into::into).collect(),
                    processing_time_ms: processing_time,
                }))
            },
            Err(e) => {
                error!("Proximity query error: {:?}", e);
                counter!("proximity.query.error", 1);
                Err(Status::internal(format!("Query error: {}", e)))
            }
        }
    }

    /// Handles streaming proximity updates with backpressure
    #[instrument(skip(self, request))]
    async fn stream_proximity_updates(
        &self,
        request: Request<tonic::Streaming<ProximityRequest>>,
    ) -> Result<Response<tonic::Streaming<ProximityResponse>>, Status> {
        let mut stream = request.into_inner();
        let (tx, rx) = tokio::sync::mpsc::channel(32);

        // Spawn streaming task with backpressure handling
        tokio::spawn(async move {
            while let Some(request) = stream.message().await? {
                if tx.capacity() == 0 {
                    // Apply backpressure by waiting
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }

                let response = self.get_nearby_points(Request::new(request)).await?;
                tx.send(response.into_inner()).await?;
            }
            Ok::<_, Status>(())
        });

        Ok(Response::new(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }
}

/// Starts the gRPC server with production configuration
#[tokio::main]
pub async fn run_server(addr: String, config: ServerConfig) -> Result<(), ServerError> {
    info!("Starting Spatial Engine gRPC server on {}", addr);

    let addr: SocketAddr = addr.parse().map_err(|e| ServerError::Configuration {
        message: format!("Invalid address: {}", e),
    })?;

    // Initialize core services
    let lidar_processor = Arc::new(LiDARProcessor::new(
        Arc::new(Mutex::new(SpatialIndex::new(None, "lidar".to_string()))),
        None,
        None,
        None,
    )?);

    let proximity_service = Arc::new(ProximityService::new(
        Arc::new(Mutex::new(SpatialIndex::new(None, "users".to_string()))),
        Arc::new(Mutex::new(SpatialIndex::new(None, "tags".to_string()))),
        lidar_processor.clone(),
    ));

    // Create server instance
    let server = SpatialServiceServer::new(
        lidar_processor,
        proximity_service,
        Some(config.clone()),
    );

    // Configure and start server
    Server::builder()
        .timeout(config.request_timeout)
        .concurrency_limit(config.max_concurrent_requests as usize)
        .add_service(spatial_engine::SpatialServiceServer::new(server))
        .serve_with_shutdown(addr, async {
            tokio::signal::ctrl_c().await.unwrap();
            info!("Shutdown signal received, starting graceful shutdown");
            tokio::time::sleep(config.graceful_shutdown_timeout).await;
        })
        .await
        .map_err(ServerError::Transport)?;

    info!("Server shutdown completed");
    Ok(())
}