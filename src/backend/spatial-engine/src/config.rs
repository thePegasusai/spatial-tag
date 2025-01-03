use config::{Config, ConfigError, Environment, File};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, error, info, instrument};
use crate::models::location::Location;

// System-wide constants based on technical specifications
const DEFAULT_MAX_SCAN_RANGE: f64 = 50.0;  // Maximum LiDAR range in meters
const DEFAULT_MIN_SCAN_RANGE: f64 = 0.5;   // Minimum LiDAR range in meters
const DEFAULT_REFRESH_RATE: u32 = 30;      // Minimum refresh rate in Hz
const DEFAULT_MAX_PROCESSING_TIME_MS: u32 = 100;  // Maximum latency requirement
const DEFAULT_BATTERY_THRESHOLD_PERCENT: u8 = 15;  // Battery usage threshold

/// Comprehensive configuration settings for the Spatial Engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    // LiDAR scanning parameters
    pub max_scan_range_meters: f64,
    pub min_scan_range_meters: f64,
    pub refresh_rate_hz: u32,
    
    // Performance constraints
    pub max_processing_time_ms: u32,
    pub battery_threshold_percent: u8,
    
    // Environment configuration
    pub debug_mode: bool,
    pub environment: String,
    pub feature_flags: HashMap<String, String>,
}

impl Settings {
    /// Creates new Settings instance with validated default values
    #[instrument]
    pub fn new() -> Self {
        let mut feature_flags = HashMap::new();
        feature_flags.insert("high_precision_mode".to_string(), "enabled".to_string());
        feature_flags.insert("battery_optimization".to_string(), "enabled".to_string());

        Settings {
            max_scan_range_meters: DEFAULT_MAX_SCAN_RANGE,
            min_scan_range_meters: DEFAULT_MIN_SCAN_RANGE,
            refresh_rate_hz: DEFAULT_REFRESH_RATE,
            max_processing_time_ms: DEFAULT_MAX_PROCESSING_TIME_MS,
            battery_threshold_percent: DEFAULT_BATTERY_THRESHOLD_PERCENT,
            debug_mode: false,
            environment: "production".to_string(),
            feature_flags,
        }
    }

    /// Builder method to set and validate scan range values
    #[instrument]
    pub fn with_scan_range(mut self, min_range: f64, max_range: f64) -> Result<Self, ConfigError> {
        if min_range < DEFAULT_MIN_SCAN_RANGE || max_range > DEFAULT_MAX_SCAN_RANGE {
            return Err(ConfigError::Message(format!(
                "Scan range must be between {} and {} meters",
                DEFAULT_MIN_SCAN_RANGE, DEFAULT_MAX_SCAN_RANGE
            )));
        }

        if min_range >= max_range {
            return Err(ConfigError::Message(
                "Minimum scan range must be less than maximum scan range".to_string()
            ));
        }

        self.min_scan_range_meters = min_range;
        self.max_scan_range_meters = max_range;
        debug!("Scan range configured: min={}, max={}", min_range, max_range);
        Ok(self)
    }

    /// Configures performance-related settings with validation
    #[instrument]
    pub fn with_performance_settings(
        mut self,
        refresh_rate: u32,
        max_processing_time: u32,
    ) -> Result<Self, ConfigError> {
        if refresh_rate < DEFAULT_REFRESH_RATE {
            return Err(ConfigError::Message(format!(
                "Refresh rate must be at least {} Hz",
                DEFAULT_REFRESH_RATE
            )));
        }

        if max_processing_time > DEFAULT_MAX_PROCESSING_TIME_MS {
            return Err(ConfigError::Message(format!(
                "Processing time must not exceed {} ms",
                DEFAULT_MAX_PROCESSING_TIME_MS
            )));
        }

        self.refresh_rate_hz = refresh_rate;
        self.max_processing_time_ms = max_processing_time;
        debug!(
            "Performance settings configured: refresh_rate={}, max_processing_time={}",
            refresh_rate, max_processing_time
        );
        Ok(self)
    }
}

/// Loads and validates configuration from environment variables and config files
#[instrument]
pub fn load_config() -> Result<Settings, ConfigError> {
    let mut builder = Config::builder();

    // Load default configuration
    let mut settings = Settings::new();

    // Layer environment-specific configuration
    builder = builder
        .add_source(File::with_name("config/spatial_engine").required(false))
        .add_source(Environment::with_prefix("SPATIAL_ENGINE"));

    // Build configuration
    match builder.build() {
        Ok(config) => {
            // Update settings from config sources
            if let Ok(val) = config.get_float("max_scan_range_meters") {
                settings = settings.with_scan_range(settings.min_scan_range_meters, val)?;
            }
            if let Ok(val) = config.get_float("min_scan_range_meters") {
                settings = settings.with_scan_range(val, settings.max_scan_range_meters)?;
            }
            if let Ok(val) = config.get_int("refresh_rate_hz") {
                settings = settings.with_performance_settings(
                    val as u32,
                    settings.max_processing_time_ms,
                )?;
            }
            if let Ok(val) = config.get_int("max_processing_time_ms") {
                settings = settings.with_performance_settings(
                    settings.refresh_rate_hz,
                    val as u32,
                )?;
            }
            if let Ok(val) = config.get_bool("debug_mode") {
                settings.debug_mode = val;
            }
            if let Ok(val) = config.get_string("environment") {
                settings.environment = val;
            }
        }
        Err(e) => {
            error!("Failed to load configuration: {}", e);
            return Err(e);
        }
    }

    // Validate final configuration
    validate_settings(&settings)?;
    info!("Configuration loaded successfully: {:?}", settings);
    Ok(settings)
}

/// Performs comprehensive validation of all configuration settings
#[instrument]
fn validate_settings(settings: &Settings) -> Result<(), ConfigError> {
    // Validate scan range
    if settings.min_scan_range_meters < DEFAULT_MIN_SCAN_RANGE
        || settings.max_scan_range_meters > DEFAULT_MAX_SCAN_RANGE
    {
        return Err(ConfigError::Message(format!(
            "Invalid scan range configuration: min={}, max={}",
            settings.min_scan_range_meters, settings.max_scan_range_meters
        )));
    }

    // Validate refresh rate
    if settings.refresh_rate_hz < DEFAULT_REFRESH_RATE {
        return Err(ConfigError::Message(format!(
            "Refresh rate must be at least {} Hz",
            DEFAULT_REFRESH_RATE
        )));
    }

    // Validate processing time
    if settings.max_processing_time_ms > DEFAULT_MAX_PROCESSING_TIME_MS {
        return Err(ConfigError::Message(format!(
            "Processing time must not exceed {} ms",
            DEFAULT_MAX_PROCESSING_TIME_MS
        )));
    }

    // Validate battery threshold
    if settings.battery_threshold_percent < 5 || settings.battery_threshold_percent > 20 {
        return Err(ConfigError::Message(
            "Battery threshold must be between 5% and 20%".to_string()
        ));
    }

    debug!("Configuration validation successful");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_settings() {
        let settings = Settings::new();
        assert_eq!(settings.max_scan_range_meters, DEFAULT_MAX_SCAN_RANGE);
        assert_eq!(settings.min_scan_range_meters, DEFAULT_MIN_SCAN_RANGE);
        assert_eq!(settings.refresh_rate_hz, DEFAULT_REFRESH_RATE);
    }

    #[test]
    fn test_scan_range_validation() {
        let settings = Settings::new()
            .with_scan_range(1.0, 45.0)
            .expect("Valid scan range should be accepted");
        assert_eq!(settings.min_scan_range_meters, 1.0);
        assert_eq!(settings.max_scan_range_meters, 45.0);
    }

    #[test]
    fn test_invalid_scan_range() {
        let result = Settings::new().with_scan_range(0.1, 60.0);
        assert!(result.is_err());
    }

    #[test]
    fn test_performance_settings() {
        let settings = Settings::new()
            .with_performance_settings(60, 50)
            .expect("Valid performance settings should be accepted");
        assert_eq!(settings.refresh_rate_hz, 60);
        assert_eq!(settings.max_processing_time_ms, 50);
    }
}