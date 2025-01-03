//
// LocationManagerTests.swift
// SpatialTagTests
//
// Comprehensive test suite for LocationManager with LiDAR and spatial awareness validation
//
// XCTest Version: iOS 15.0+
// CoreLocation Version: iOS 15.0+
// Combine Version: iOS 15.0+
//

import XCTest
import CoreLocation
import Combine
@testable import SpatialTag

// MARK: - Constants

private enum TestConstants {
    static let TEST_TIMEOUT: TimeInterval = 5.0
    static let TEST_LOCATION_ACCURACY: CLLocationAccuracy = kCLLocationAccuracyBest
    static let LIDAR_MIN_RANGE: Double = 0.5
    static let LIDAR_MAX_RANGE: Double = 50.0
    static let PRECISION_THRESHOLD: Double = 0.01 // ±1cm precision at 10m
    static let PERFORMANCE_THRESHOLD: Double = 0.1 // 100ms threshold
}

final class LocationManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: LocationManager!
    private var cancellables: Set<AnyCancellable>!
    private var locationExpectation: XCTestExpectation!
    private var testQueue: DispatchQueue!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        sut = LocationManager()
        cancellables = Set<AnyCancellable>()
        testQueue = DispatchQueue(label: "com.spatialtag.test.location")
        locationExpectation = expectation(description: "Location Update")
    }
    
    override func tearDown() {
        sut.stopUpdatingLocation()
        cancellables.removeAll()
        sut = nil
        testQueue = nil
        super.tearDown()
    }
    
    // MARK: - Location Service Tests
    
    func testLocationPermissionRequest() {
        let permissionExpectation = expectation(description: "Permission Request")
        
        sut.requestLocationPermission()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Permission request failed: \(error)")
                    }
                },
                receiveValue: { status in
                    XCTAssertTrue(status == .authorizedWhenInUse || status == .authorizedAlways)
                    permissionExpectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [permissionExpectation], timeout: TestConstants.TEST_TIMEOUT)
    }
    
    func testLocationUpdates() {
        let updateExpectation = expectation(description: "Location Updates")
        updateExpectation.expectedFulfillmentCount = 3
        
        sut.startUpdatingLocation()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Location updates failed: \(error)")
                    }
                },
                receiveValue: { location in
                    XCTAssertNotNil(location)
                    XCTAssertTrue(location.coordinate.isValid())
                    updateExpectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [updateExpectation], timeout: TestConstants.TEST_TIMEOUT)
    }
    
    // MARK: - Spatial Precision Tests
    
    func testLocationPrecision() {
        let precisionExpectation = expectation(description: "Precision Test")
        
        // Test locations at different distances
        let testDistances: [(distance: Double, expectedPrecision: Double)] = [
            (5.0, 0.01),   // ±1cm at 5m
            (10.0, 0.01),  // ±1cm at 10m
            (25.0, 0.02),  // ±2cm at 25m
            (50.0, 0.05)   // ±5cm at 50m
        ]
        
        var precisionResults: [(distance: Double, actualPrecision: Double)] = []
        
        testQueue.async {
            for test in testDistances {
                guard let baseLocation = self.createTestLocation(distance: test.distance) else {
                    XCTFail("Failed to create test location")
                    return
                }
                
                // Measure precision at each distance
                if let precision = self.measureSpatialPrecision(at: baseLocation) {
                    precisionResults.append((test.distance, precision))
                }
            }
            
            // Verify precision requirements
            for (index, result) in precisionResults.enumerated() {
                let expectedPrecision = testDistances[index].expectedPrecision
                XCTAssertLessThanOrEqual(
                    abs(result.actualPrecision - expectedPrecision),
                    TestConstants.PRECISION_THRESHOLD,
                    "Precision at \(result.distance)m exceeded threshold"
                )
            }
            
            precisionExpectation.fulfill()
        }
        
        wait(for: [precisionExpectation], timeout: TestConstants.TEST_TIMEOUT)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceMetrics() {
        measure {
            let performanceExpectation = expectation(description: "Performance Test")
            
            let startTime = DispatchTime.now()
            
            sut.startUpdatingLocation()
                .prefix(10) // Test with 10 location updates
                .collect()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            XCTFail("Performance test failed: \(error)")
                        }
                    },
                    receiveValue: { locations in
                        let endTime = DispatchTime.now()
                        let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                        
                        // Verify performance requirements
                        let averageResponseTime = duration / Double(locations.count)
                        XCTAssertLessThanOrEqual(
                            averageResponseTime,
                            TestConstants.PERFORMANCE_THRESHOLD,
                            "Average response time exceeded threshold"
                        )
                        
                        performanceExpectation.fulfill()
                    }
                )
                .store(in: &cancellables)
            
            wait(for: [performanceExpectation], timeout: TestConstants.TEST_TIMEOUT)
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testThreadSafety() {
        let threadSafetyExpectation = expectation(description: "Thread Safety")
        threadSafetyExpectation.expectedFulfillmentCount = 2
        
        let concurrentQueue = DispatchQueue(
            label: "com.spatialtag.test.concurrent",
            attributes: .concurrent
        )
        
        // Test concurrent location operations
        concurrentQueue.async {
            self.sut.startUpdatingLocation()
                .prefix(5)
                .sink(
                    receiveCompletion: { _ in
                        threadSafetyExpectation.fulfill()
                    },
                    receiveValue: { _ in }
                )
                .store(in: &self.cancellables)
        }
        
        concurrentQueue.async {
            self.sut.findNearbyUsers(radius: 10.0, requiredAccuracy: TestConstants.TEST_LOCATION_ACCURACY)
                .prefix(5)
                .sink(
                    receiveCompletion: { _ in
                        threadSafetyExpectation.fulfill()
                    },
                    receiveValue: { _ in }
                )
                .store(in: &self.cancellables)
        }
        
        wait(for: [threadSafetyExpectation], timeout: TestConstants.TEST_TIMEOUT)
    }
    
    // MARK: - Helper Methods
    
    private func createTestLocation(distance: Double) -> Location? {
        let coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        do {
            return try Location(
                coordinate: coordinate,
                altitude: 0,
                spatialCoordinate: simd_float3(Float(distance), 0, 0)
            )
        } catch {
            return nil
        }
    }
    
    private func measureSpatialPrecision(at location: Location) -> Double? {
        // Simulate multiple measurements to calculate precision
        let measurements = (0..<10).compactMap { _ -> Double? in
            if case .success(let distance) = location.distanceTo(location) {
                return distance
            }
            return nil
        }
        
        guard !measurements.isEmpty else { return nil }
        
        // Calculate standard deviation as precision metric
        let mean = measurements.reduce(0, +) / Double(measurements.count)
        let variance = measurements.map { pow($0 - mean, 2) }.reduce(0, +) / Double(measurements.count)
        return sqrt(variance)
    }
}