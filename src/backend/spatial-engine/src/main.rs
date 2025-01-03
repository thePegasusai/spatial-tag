//! Entry point for the Spatial Engine service providing LiDAR-based spatial processing
//! and proximity detection capabilities with comprehensive monitoring and graceful shutdown.
//! 
//! Version: 1.0.0

use anyhow::{Context, Result};
use metrics::{counter, gauge};
use tokio::signal;
use tracing::{debug, error, info, warn};
use tracing_subscriber::{EnvFilter, FmtSubscriber};

use crate::config::{Settings, load_config};
use crate::grpc::server::{run_server, ServerConfig};
use crate::services::init_spatial_services;

// Default server address from technical specifications
const DEFAULT_SERVER_ADDR: &str = "[::1]:50051";

/// Application entry point with comprehensive initialization and monitoring
#[tokio::main]
async fn main() -> Result<()> {
    // Initialize structured logging with environment-based filters
    setup_logging()?;
    info!("Starting Spatial Tag Engine service");

    // Initialize metrics collection
    metrics::register_counter!("spatial_engine.startup");
    metrics::register_gauge!("spatial_engine.uptime_seconds");
    counter!("spatial_engine.startup", 1);

    // Load and validate configuration
    let config = load_config()
        .context("Failed to load configuration")?;
    debug!("Configuration loaded successfully: {:?}", config);

    // Initialize spatial services
    init_spatial_services()
        .context("Failed to initialize spatial services")?;
    info!("Spatial services initialized successfully");

    // Configure server settings
    let server_config = ServerConfig::default();
    let addr = std::env::var("SPATIAL_ENGINE_ADDR")
        .unwrap_or_else(|_| DEFAULT_SERVER_ADDR.to_string());

    // Start uptime monitoring
    let start_time = std::time::Instant::now();
    tokio::spawn(async move {
        loop {
            gauge!("spatial_engine.uptime_seconds", start_time.elapsed().as_secs_f64());
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    });

    // Run server with graceful shutdown handling
    info!("Starting gRPC server on {}", addr);
    let server_handle = tokio::spawn(run_server(addr, server_config));

    // Wait for shutdown signal
    match signal::ctrl_c().await {
        Ok(()) => {
            info!("Shutdown signal received, initiating graceful shutdown");
            handle_shutdown().await?;
        }
        Err(err) => {
            error!("Failed to listen for shutdown signal: {}", err);
            handle_shutdown().await?;
        }
    }

    // Wait for server to complete shutdown
    if let Err(e) = server_handle.await {
        error!("Server shutdown error: {}", e);
    }

    info!("Spatial Tag Engine shutdown completed");
    Ok(())
}

/// Initializes structured logging with appropriate filters and formatting
fn setup_logging() -> Result<()> {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    let subscriber = FmtSubscriber::builder()
        .with_env_filter(env_filter)
        .with_thread_ids(true)
        .with_target(false)
        .with_file(true)
        .with_line_number(true)
        .pretty()
        .try_init()
        .context("Failed to initialize logging subscriber")?;

    debug!("Logging initialized successfully");
    Ok(())
}

/// Handles graceful shutdown with resource cleanup
async fn handle_shutdown() -> Result<()> {
    info!("Beginning graceful shutdown sequence");

    // Allow time for pending requests to complete
    tokio::time::sleep(std::time::Duration::from_secs(5)).await;

    // Record shutdown metrics
    counter!("spatial_engine.shutdown", 1);
    
    info!("Graceful shutdown completed");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_setup_logging() {
        assert!(setup_logging().is_ok());
    }

    #[tokio::test]
    async fn test_handle_shutdown() {
        assert!(handle_shutdown().await.is_ok());
    }
}