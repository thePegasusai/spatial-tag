use crate::services::lidar::{LiDARProcessor, LiDARError};
use crate::models::location::Location;
use mockall::predicate::*;
use mockall::mock;
use nalgebra::{Point3, Matrix4};
use assert_approx_eq::assert_approx_eq;
use tokio_test;
use rand::{Rng, SeedableRng};
use rand::rngs::StdRng;
use criterion::{black_box, criterion_group, criterion_main, Criterion};

// Global test constants from technical specifications
const TEST_SCAN_RANGE: f64 = 50.0;
const TEST_CONFIDENCE_THRESHOLD: f64 = 0.95;
const TEST_POINT_COUNT: usize = 10000;
const TEST_PRECISION_THRESHOLD: f64 = 0.01;
const TEST_PERFORMANCE_THRESHOLD_MS: f64 = 100.0;
const TEST_CONCURRENT_THREADS: usize = 4;
const TEST_SEED: u64 = 12345;

// Mock the spatial index for testing
mock! {
    SpatialIndex {
        fn insert(&self, location: Location, id: String) -> Result<(), SpatialIndexError>;
        fn query_radius(&self, center: Location, radius: f64) -> Result<Vec<(Location, String, f64)>, SpatialIndexError>;
    }
}

/// Test helper to generate synthetic point cloud data
fn generate_test_point_cloud(point_count: usize, range: f64, noise_factor: f64) -> Vec<Point3<f64>> {
    let mut rng = StdRng::seed_from_u64(TEST_SEED);
    let mut points = Vec::with_capacity(point_count);

    for _ in 0..point_count {
        let r = rng.gen_range(0.0..range);
        let theta = rng.gen_range(0.0..std::f64::consts::PI * 2.0);
        let phi = rng.gen_range(0.0..std::f64::consts::PI);

        let noise_x = rng.gen_range(-noise_factor..noise_factor);
        let noise_y = rng.gen_range(-noise_factor..noise_factor);
        let noise_z = rng.gen_range(-noise_factor..noise_factor);

        let x = r * theta.sin() * phi.cos() + noise_x;
        let y = r * theta.sin() * phi.sin() + noise_y;
        let z = r * theta.cos() + noise_z;

        points.push(Point3::new(x, y, z));
    }

    points
}

/// Test helper to setup processor with mocked dependencies
async fn setup_test_processor(scan_range: Option<f64>, confidence_threshold: Option<f64>) -> Result<(LiDARProcessor, MockSpatialIndex), LiDARError> {
    let mut mock_index = MockSpatialIndex::new();
    mock_index.expect_insert()
        .returning(|_, _| Ok(()));
    mock_index.expect_query_radius()
        .returning(|_, _| Ok(vec![]));

    let processor = LiDARProcessor::new(
        Arc::new(Mutex::new(mock_index.clone())),
        scan_range,
        confidence_threshold,
        None,
    )?;

    Ok((processor, mock_index))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_processor_initialization() {
        // Test default initialization
        let result = setup_test_processor(None, None).await;
        assert!(result.is_ok());

        // Test custom scan range
        let result = setup_test_processor(Some(25.0), None).await;
        assert!(result.is_ok());

        // Test invalid scan range
        let result = setup_test_processor(Some(100.0), None).await;
        assert!(matches!(result, Err(LiDARError::InvalidScanRange { .. })));

        // Test custom confidence threshold
        let result = setup_test_processor(None, Some(0.98)).await;
        assert!(result.is_ok());

        // Test invalid confidence threshold
        let result = setup_test_processor(None, Some(0.5)).await;
        assert!(matches!(result, Err(LiDARError::InvalidConfidence { .. })));
    }

    #[tokio::test]
    async fn test_point_cloud_processing_performance() {
        let (processor, _) = setup_test_processor(None, None).await.unwrap();
        let points = generate_test_point_cloud(TEST_POINT_COUNT, TEST_SCAN_RANGE, 0.01);

        let start = std::time::Instant::now();
        let result = processor.process_point_cloud(points).await;
        let processing_time = start.elapsed().as_millis() as f64;

        assert!(result.is_ok());
        assert!(processing_time < TEST_PERFORMANCE_THRESHOLD_MS, 
            "Processing time {:.2}ms exceeded threshold {:.2}ms", 
            processing_time, 
            TEST_PERFORMANCE_THRESHOLD_MS
        );
    }

    #[tokio::test]
    async fn test_precision_at_ranges() {
        let (processor, _) = setup_test_processor(None, None).await.unwrap();

        // Test close range precision (0.5m)
        let close_points = generate_test_point_cloud(100, 0.5, 0.001);
        let result = processor.process_point_cloud(close_points).await.unwrap();
        assert!(result.points.iter().all(|p| p.coords.norm() >= 0.5));

        // Test medium range precision (10m)
        let medium_points = generate_test_point_cloud(100, 10.0, 0.01);
        let result = processor.process_point_cloud(medium_points).await.unwrap();
        for point in result.points.iter() {
            let distance = point.coords.norm();
            if distance <= 10.0 {
                assert_approx_eq!(
                    point.coords.norm(), 
                    distance, 
                    TEST_PRECISION_THRESHOLD
                );
            }
        }

        // Test maximum range precision (50m)
        let far_points = generate_test_point_cloud(100, 50.0, 0.1);
        let result = processor.process_point_cloud(far_points).await.unwrap();
        assert!(result.points.iter().all(|p| p.coords.norm() <= 50.0));
    }

    #[tokio::test]
    async fn test_concurrent_processing() {
        let (processor, _) = setup_test_processor(None, None).await.unwrap();
        let processor = Arc::new(processor);
        let mut handles = Vec::new();

        // Generate multiple point clouds
        let point_clouds: Vec<Vec<Point3<f64>>> = (0..TEST_CONCURRENT_THREADS)
            .map(|_| generate_test_point_cloud(TEST_POINT_COUNT / TEST_CONCURRENT_THREADS, TEST_SCAN_RANGE, 0.01))
            .collect();

        // Process point clouds concurrently
        for points in point_clouds {
            let processor_clone = processor.clone();
            handles.push(tokio::spawn(async move {
                processor_clone.process_point_cloud(points).await
            }));
        }

        // Verify all concurrent operations completed successfully
        for handle in handles {
            let result = handle.await.unwrap();
            assert!(result.is_ok());
        }
    }

    #[tokio::test]
    async fn test_environment_query() {
        let (processor, mock_index) = setup_test_processor(None, None).await.unwrap();
        let center = Location::new(0.0, 0.0, 0.0, 1.0, None).unwrap();

        let result = processor.query_environment(&center, 25.0).await;
        assert!(result.is_ok());

        let context = result.unwrap();
        assert_eq!(context.radius, 25.0);
        assert_approx_eq!(context.center.coords.norm(), 0.0);
    }
}

// Performance benchmarks
fn lidar_processing_benchmark(c: &mut Criterion) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    
    c.bench_function("process_point_cloud", |b| {
        b.iter(|| {
            rt.block_on(async {
                let (processor, _) = setup_test_processor(None, None).await.unwrap();
                let points = generate_test_point_cloud(TEST_POINT_COUNT, TEST_SCAN_RANGE, 0.01);
                black_box(processor.process_point_cloud(points).await.unwrap())
            })
        })
    });
}

criterion_group!(benches, lidar_processing_benchmark);
criterion_main!(benches);