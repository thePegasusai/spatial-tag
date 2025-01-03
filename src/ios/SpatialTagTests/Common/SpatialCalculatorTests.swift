//
// SpatialCalculatorTests.swift
// SpatialTagTests
//
// Comprehensive test suite for validating SpatialCalculator functionality
// including LiDAR integration, precision requirements, and performance metrics
//

import XCTest
import CoreLocation
import simd
import ARKit
@testable import SpatialTag

// MARK: - Constants

private let DISTANCE_PRECISION_THRESHOLD = 0.01 // ±1cm precision threshold
private let TEST_LATITUDE = 37.7749
private let TEST_LONGITUDE = -122.4194
private let TEST_ALTITUDE = 10.0
private let MIN_DETECTION_RANGE = 0.5
private let MAX_DETECTION_RANGE = 50.0
private let PERFORMANCE_THRESHOLD_MS = 100.0
private let CONCURRENT_TEST_COUNT = 10

class SpatialCalculatorTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: SpatialCalculator!
    private var referenceLocation: CLLocation!
    private var concurrencyExpectation: XCTestExpectation!
    private var testQueue: DispatchQueue!
    private var arConfig: ARWorldTrackingConfiguration!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize reference location
        referenceLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: TEST_LATITUDE,
                longitude: TEST_LONGITUDE
            ),
            altitude: TEST_ALTITUDE,
            horizontalAccuracy: 1.0,
            verticalAccuracy: 1.0,
            timestamp: Date()
        )
        
        // Initialize SpatialCalculator
        sut = SpatialCalculator(referenceLocation: referenceLocation)
        
        // Configure AR session for LiDAR testing
        arConfig = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            arConfig.sceneReconstruction = .mesh
        }
        
        // Setup concurrent testing queue
        testQueue = DispatchQueue(label: "com.spatialtag.test.concurrent",
                                attributes: .concurrent)
        
        // Initialize test expectations
        concurrencyExpectation = expectation(description: "Concurrent operations")
        concurrencyExpectation.expectedFulfillmentCount = CONCURRENT_TEST_COUNT
    }
    
    override func tearDown() {
        sut = nil
        referenceLocation = nil
        concurrencyExpectation = nil
        testQueue = nil
        arConfig = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testSpatialDistanceCalculation() throws {
        // Create test locations
        let location1 = try Location(
            coordinate: CLLocationCoordinate2D(
                latitude: TEST_LATITUDE,
                longitude: TEST_LONGITUDE
            ),
            altitude: TEST_ALTITUDE,
            spatialCoordinate: simd_float3(0, 0, 0)
        )
        
        let location2 = try Location(
            coordinate: CLLocationCoordinate2D(
                latitude: TEST_LATITUDE + 0.001,
                longitude: TEST_LONGITUDE + 0.001
            ),
            altitude: TEST_ALTITUDE + 5.0,
            spatialCoordinate: simd_float3(10, 0, 0)
        )
        
        // Test distance calculation with LiDAR
        measure {
            let result = sut.calculateSpatialDistance(
                location1: location1,
                location2: location2,
                useLiDAR: true
            )
            
            switch result {
            case .success(let distance):
                // Verify precision at 10m range
                XCTAssertEqual(distance, 10.0, accuracy: DISTANCE_PRECISION_THRESHOLD)
                XCTAssertGreaterThanOrEqual(distance, MIN_DETECTION_RANGE)
                XCTAssertLessThanOrEqual(distance, MAX_DETECTION_RANGE)
            case .failure(let error):
                XCTFail("Distance calculation failed with error: \(error)")
            }
        }
        
        // Test concurrent calculations
        for _ in 0..<CONCURRENT_TEST_COUNT {
            testQueue.async {
                let result = self.sut.calculateSpatialDistance(
                    location1: location1,
                    location2: location2,
                    useLiDAR: true
                )
                
                if case .success(let distance) = result {
                    XCTAssertEqual(distance, 10.0, accuracy: self.DISTANCE_PRECISION_THRESHOLD)
                }
                
                self.concurrencyExpectation.fulfill()
            }
        }
        
        wait(for: [concurrencyExpectation], timeout: 5.0)
    }
    
    func testCoordinateTransformation() throws {
        // Create test locations with varying altitudes
        let testLocations = try (0...5).map { index in
            try Location(
                coordinate: CLLocationCoordinate2D(
                    latitude: TEST_LATITUDE + Double(index) * 0.001,
                    longitude: TEST_LONGITUDE + Double(index) * 0.001
                ),
                altitude: TEST_ALTITUDE + Double(index) * 10.0,
                spatialCoordinate: simd_float3(Float(index) * 10.0, 0, 0)
            )
        }
        
        // Test coordinate transformations
        for location in testLocations {
            let result = sut.calculateSpatialDistance(
                location1: testLocations[0],
                location2: location,
                useLiDAR: true
            )
            
            switch result {
            case .success(let distance):
                let expectedDistance = Float(simd_length(
                    location.spatialCoordinate! - testLocations[0].spatialCoordinate!
                ))
                XCTAssertEqual(distance, Double(expectedDistance), accuracy: DISTANCE_PRECISION_THRESHOLD)
            case .failure(let error):
                XCTFail("Transformation failed with error: \(error)")
            }
        }
        
        // Test concurrent transformations
        for location in testLocations {
            testQueue.async {
                let result = self.sut.calculateSpatialDistance(
                    location1: testLocations[0],
                    location2: location,
                    useLiDAR: true
                )
                
                if case .success(let distance) = result {
                    let expectedDistance = Float(simd_length(
                        location.spatialCoordinate! - testLocations[0].spatialCoordinate!
                    ))
                    XCTAssertEqual(distance, Double(expectedDistance),
                                 accuracy: self.DISTANCE_PRECISION_THRESHOLD)
                }
            }
        }
    }
    
    func testDetectionRangeValidation() throws {
        // Test minimum range detection
        let minRangeLocation = try Location(
            coordinate: referenceLocation.coordinate,
            altitude: referenceLocation.altitude,
            spatialCoordinate: simd_float3(Float(MIN_DETECTION_RANGE), 0, 0)
        )
        
        let minRangeResult = sut.isInDetectionRange(minRangeLocation)
        XCTAssertEqual(try XCTUnwrap(minRangeResult.get()), true)
        
        // Test maximum range detection
        let maxRangeLocation = try Location(
            coordinate: referenceLocation.coordinate,
            altitude: referenceLocation.altitude,
            spatialCoordinate: simd_float3(Float(MAX_DETECTION_RANGE), 0, 0)
        )
        
        let maxRangeResult = sut.isInDetectionRange(maxRangeLocation)
        XCTAssertEqual(try XCTUnwrap(maxRangeResult.get()), true)
        
        // Test out of range detection
        let outOfRangeLocation = try Location(
            coordinate: referenceLocation.coordinate,
            altitude: referenceLocation.altitude,
            spatialCoordinate: simd_float3(Float(MAX_DETECTION_RANGE + 1), 0, 0)
        )
        
        let outOfRangeResult = sut.isInDetectionRange(outOfRangeLocation)
        XCTAssertEqual(try XCTUnwrap(outOfRangeResult.get()), false)
    }
    
    func testWorldTransformUpdate() {
        // Create test transform matrices
        let translation = matrix_float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(10, 0, 0, 1)
        )
        
        // Test concurrent transform updates
        for _ in 0..<CONCURRENT_TEST_COUNT {
            testQueue.async {
                let result = self.sut.updateWorldTransform(translation)
                XCTAssertTrue(result)
                self.concurrencyExpectation.fulfill()
            }
        }
        
        wait(for: [concurrencyExpectation], timeout: 5.0)
    }
}