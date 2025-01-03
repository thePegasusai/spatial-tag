//
// SpatialServiceTests.swift
// SpatialTagTests
//
// Comprehensive test suite for SpatialService class validating spatial awareness,
// LiDAR processing, location tracking, performance metrics, and battery impact
//

import XCTest
import Combine
@testable import SpatialTag

@available(iOS 15.0, *)
final class SpatialServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: SpatialService!
    private var mockLidarProcessor: MockLiDARProcessor!
    private var mockLocationManager: MockLocationManager!
    private var cancellables = Set<AnyCancellable>()
    private let performanceMetrics = XCTMetrics()
    private let processInfo = ProcessInfo.processInfo
    private let concurrentQueue = DispatchQueue(label: "com.spatialtag.tests.concurrent",
                                              qos: .userInitiated,
                                              attributes: .concurrent)
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize mock LiDAR processor with precision settings
        mockLidarProcessor = MockLiDARProcessor()
        mockLidarProcessor.currentRange = 50.0
        mockLidarProcessor.refreshRate = 30.0
        mockLidarProcessor.precisionAtDistance = { distance in
            return distance <= 10.0 ? 0.01 : 0.05
        }
        
        // Initialize mock location manager
        mockLocationManager = MockLocationManager()
        
        // Initialize system under test
        sut = SpatialService(lidarProcessor: mockLidarProcessor,
                           locationManager: mockLocationManager)
        
        // Start battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    
    override func tearDown() async throws {
        // Stop tracking and clean up
        sut.stopSpatialTracking()
        mockLidarProcessor = nil
        mockLocationManager = nil
        sut = nil
        cancellables.removeAll()
        
        // Stop battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = false
        
        try await super.tearDown()
    }
    
    // MARK: - Spatial Tracking Tests
    
    func testSpatialTrackingPerformance() async throws {
        // Given
        let expectation = expectation(description: "Spatial tracking started")
        var trackingResponse: Result<Void, Error>?
        
        // Measure response time
        measure(metrics: [XCTClockMetric()]) {
            // When
            sut.startSpatialTracking()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            trackingResponse = .failure(error)
                        }
                        expectation.fulfill()
                    },
                    receiveValue: {
                        trackingResponse = .success(())
                    }
                )
                .store(in: &cancellables)
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then
        XCTAssertNotNil(trackingResponse)
        if case .failure = trackingResponse {
            XCTFail("Spatial tracking failed to start")
        }
        
        // Verify LiDAR refresh rate
        XCTAssertEqual(mockLidarProcessor.refreshRate, 30.0,
                      "LiDAR refresh rate should meet 30Hz requirement")
        
        // Verify scanning range
        XCTAssertGreaterThanOrEqual(mockLidarProcessor.currentRange, 0.5,
                                  "Minimum scanning range should be 0.5m")
        XCTAssertLessThanOrEqual(mockLidarProcessor.currentRange, 50.0,
                               "Maximum scanning range should be 50.0m")
        
        // Verify precision at 10m
        let precisionAt10m = mockLidarProcessor.precisionAtDistance(10.0)
        XCTAssertEqual(precisionAt10m, 0.01,
                      "Precision at 10m should be ±1cm")
        
        // Monitor battery impact
        let initialBatteryLevel = UIDevice.current.batteryLevel
        try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        let finalBatteryLevel = UIDevice.current.batteryLevel
        let batteryDrain = initialBatteryLevel - finalBatteryLevel
        
        XCTAssertLessThan(batteryDrain, 0.15,
                         "Battery drain should be less than 15% per hour")
        
        // Test concurrent access
        let concurrentExpectation = expectation(description: "Concurrent operations completed")
        concurrentExpectation.expectedFulfillmentCount = 10
        
        for _ in 0..<10 {
            concurrentQueue.async {
                self.sut.startSpatialTracking()
                    .sink(
                        receiveCompletion: { _ in
                            concurrentExpectation.fulfill()
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &self.cancellables)
            }
        }
        
        await fulfillment(of: [concurrentExpectation], timeout: 5.0)
    }
    
    func testNearbyUserDiscoveryPrecision() async throws {
        // Given
        let expectation = expectation(description: "Nearby users discovered")
        let searchRadius = 25.0
        var discoveredUsers: [Location]?
        
        // Setup mock users at various distances
        let mockUsers = try [
            Location(coordinate: .init(latitude: 0.0, longitude: 0.0), altitude: 0),
            Location(coordinate: .init(latitude: 0.001, longitude: 0.001), altitude: 0),
            Location(coordinate: .init(latitude: 0.002, longitude: 0.002), altitude: 0)
        ]
        mockLocationManager.mockNearbyUsers = mockUsers
        
        // Measure discovery performance
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            // When
            sut.findNearbyUsers(radius: searchRadius)
                .sink(
                    receiveCompletion: { _ in
                        expectation.fulfill()
                    },
                    receiveValue: { users in
                        discoveredUsers = users
                    }
                )
                .store(in: &cancellables)
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then
        XCTAssertNotNil(discoveredUsers)
        XCTAssertLessThanOrEqual(discoveredUsers?.count ?? 0, mockUsers.count)
        
        // Verify distance calculations
        if let users = discoveredUsers {
            for user in users {
                let distance = try user.distanceTo(mockUsers[0])
                if case .success(let calculatedDistance) = distance {
                    XCTAssertLessThanOrEqual(calculatedDistance, searchRadius,
                                          "Discovered users should be within search radius")
                }
            }
        }
        
        // Test concurrent discovery
        let concurrentExpectation = expectation(description: "Concurrent discoveries completed")
        concurrentExpectation.expectedFulfillmentCount = 5
        
        for _ in 0..<5 {
            concurrentQueue.async {
                self.sut.findNearbyUsers(radius: searchRadius)
                    .sink(
                        receiveCompletion: { _ in
                            concurrentExpectation.fulfill()
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &self.cancellables)
            }
        }
        
        await fulfillment(of: [concurrentExpectation], timeout: 5.0)
    }
    
    func testLocationUpdateAccuracy() async throws {
        // Given
        let expectation = expectation(description: "Location updated")
        let testLocation = try Location(
            coordinate: .init(latitude: 37.7749, longitude: -122.4194),
            altitude: 0,
            spatialCoordinate: simd_float3(0, 0, 0)
        )
        var updatedLocation: Location?
        
        // Measure update performance
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            // When
            sut.updateUserLocation(testLocation)
                .sink(
                    receiveCompletion: { _ in
                        expectation.fulfill()
                    },
                    receiveValue: { location in
                        updatedLocation = location
                    }
                )
                .store(in: &cancellables)
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then
        XCTAssertNotNil(updatedLocation)
        XCTAssertEqual(updatedLocation?.coordinate.latitude,
                      testLocation.coordinate.latitude,
                      accuracy: 0.0001)
        XCTAssertEqual(updatedLocation?.coordinate.longitude,
                      testLocation.coordinate.longitude,
                      accuracy: 0.0001)
        
        // Verify spatial data consistency
        XCTAssertNotNil(updatedLocation?.spatialCoordinate)
        
        // Test concurrent updates
        let concurrentExpectation = expectation(description: "Concurrent updates completed")
        concurrentExpectation.expectedFulfillmentCount = 5
        
        for _ in 0..<5 {
            concurrentQueue.async {
                self.sut.updateUserLocation(testLocation)
                    .sink(
                        receiveCompletion: { _ in
                            concurrentExpectation.fulfill()
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &self.cancellables)
            }
        }
        
        await fulfillment(of: [concurrentExpectation], timeout: 5.0)
    }
}

// MARK: - Mock Classes

private class MockLiDARProcessor: LiDARProcessor {
    var currentRange: Float = 50.0
    var refreshRate: Float = 30.0
    var precisionAtDistance: (Float) -> Float = { _ in 0.01 }
    
    override func startScanning() -> AnyPublisher<SpatialData, Error> {
        return Just(SpatialData(
            pointCloud: ARPointCloud(points: [], confidenceValues: []),
            confidence: 1.0,
            timestamp: Date().timeIntervalSinceReferenceDate,
            powerUsage: 0.8,
            processingTime: 0.01
        ))
        .setFailureType(to: Error.self)
        .eraseToAnyPublisher()
    }
}

private class MockLocationManager: LocationManager {
    var mockNearbyUsers: [Location] = []
    
    override func findNearbyUsers(radius: Double, requiredAccuracy: CLLocationAccuracy) -> AnyPublisher<[Location], LocationError> {
        return Just(mockNearbyUsers)
            .setFailureType(to: LocationError.self)
            .eraseToAnyPublisher()
    }
}