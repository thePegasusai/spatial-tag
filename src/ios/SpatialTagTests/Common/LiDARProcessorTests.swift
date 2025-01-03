//
// LiDARProcessorTests.swift
// SpatialTagTests
//
// Comprehensive test suite for validating LiDARProcessor functionality
// including performance specifications, spatial mapping capabilities,
// power optimization, and thread safety
//

import XCTest // latest
import ARKit // 6.0
import Combine // latest
import simd // latest
@testable import SpatialTag

final class LiDARProcessorTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: LiDARProcessor!
    private var mockSession: ARSession!
    private var mockCalculator: SpatialCalculator!
    private var powerMonitor: PowerMonitor!
    private var testQueue: DispatchQueue!
    private var cancellables: Set<AnyCancellable>!
    
    // Test constants from specifications
    private let testLidarMinRange: Float = 0.5
    private let testLidarMaxRange: Float = 50.0
    private let testLidarRefreshRate: Float = 30.0
    private let testLidarPrecision: Float = 0.01
    private let testLidarFOV: Float = 120.0
    private let testPowerThreshold: Float = 0.8
    
    // MARK: - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize test queue
        testQueue = DispatchQueue(label: "com.spatialtag.test.lidar", qos: .userInitiated)
        
        // Initialize mock AR session
        mockSession = ARSession()
        
        // Initialize mock spatial calculator with test location
        let testLocation = CLLocation(latitude: 0, longitude: 0)
        mockCalculator = SpatialCalculator(referenceLocation: testLocation)
        
        // Initialize power monitor
        powerMonitor = PowerMonitor()
        
        // Initialize cancellables set
        cancellables = Set<AnyCancellable>()
        
        // Initialize system under test
        sut = LiDARProcessor(session: mockSession, calculator: mockCalculator, powerMonitor: powerMonitor)
    }
    
    override func tearDown() {
        sut.stopScanning()
        cancellables.removeAll()
        sut = nil
        mockSession = nil
        mockCalculator = nil
        powerMonitor = nil
        testQueue = nil
        super.tearDown()
    }
    
    // MARK: - Scanning Range Tests
    
    func testMinimumScanningRange() {
        let expectation = expectation(description: "Minimum range detection")
        
        // Configure test point cloud at minimum range
        let testPoints = [simd_float3(x: 0, y: 0, z: testLidarMinRange)]
        let testConfidence: Float = 1.0
        
        // Start scanning
        sut.startScanning()
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Scanning failed with error: \(error)")
                }
            }, receiveValue: { spatialData in
                // Verify point detection at minimum range
                XCTAssertEqual(spatialData.pointCloud.points.first?.z, self.testLidarMinRange, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(spatialData.confidence, 0.85)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMaximumScanningRange() {
        let expectation = expectation(description: "Maximum range detection")
        
        // Configure test point cloud at maximum range
        let testPoints = [simd_float3(x: 0, y: 0, z: testLidarMaxRange)]
        let testConfidence: Float = 1.0
        
        sut.startScanning()
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Scanning failed with error: \(error)")
                }
            }, receiveValue: { spatialData in
                // Verify point detection at maximum range
                XCTAssertEqual(spatialData.pointCloud.points.first?.z, self.testLidarMaxRange, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(spatialData.confidence, 0.85)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Refresh Rate Tests
    
    func testRefreshRatePerformance() {
        let expectation = expectation(description: "Refresh rate validation")
        let frameCount = 100
        var processingTimes: [TimeInterval] = []
        
        sut.startScanning()
            .prefix(frameCount)
            .collect()
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Scanning failed with error: \(error)")
                }
            }, receiveValue: { spatialDataArray in
                // Calculate average processing time
                processingTimes = spatialDataArray.map { $0.processingTime }
                let averageProcessingTime = processingTimes.reduce(0, +) / Double(frameCount)
                
                // Verify minimum 30Hz refresh rate (33.33ms per frame)
                XCTAssertLessThanOrEqual(averageProcessingTime, 0.03333)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Precision Tests
    
    func testPrecisionAtTenMeters() {
        let expectation = expectation(description: "Precision validation")
        let testDistance: Float = 10.0
        let requiredPrecision: Float = 0.01 // ±1cm at 10m
        
        // Configure test points at 10m distance
        let testPoints = [simd_float3(x: 0, y: 0, z: testDistance)]
        
        sut.startScanning()
            .prefix(50) // Collect multiple samples
            .collect()
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Scanning failed with error: \(error)")
                }
            }, receiveValue: { spatialDataArray in
                // Calculate measurement variance
                let measurements = spatialDataArray.map { $0.pointCloud.points.first?.z ?? 0 }
                let variance = self.calculateVariance(measurements)
                
                // Verify precision within ±1cm
                XCTAssertLessThanOrEqual(Float(variance), requiredPrecision)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Power Usage Tests
    
    func testPowerOptimization() {
        let expectation = expectation(description: "Power usage validation")
        
        sut.startScanning()
            .prefix(100) // Monitor power usage over 100 frames
            .collect()
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    XCTFail("Scanning failed with error: \(error)")
                }
            }, receiveValue: { spatialDataArray in
                // Calculate average power usage
                let averagePowerUsage = spatialDataArray.map { $0.powerUsage }.reduce(0, +) / Float(spatialDataArray.count)
                
                // Verify power usage below 0.8W threshold
                XCTAssertLessThanOrEqual(averagePowerUsage, self.testPowerThreshold)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentScanning() {
        let expectation = expectation(description: "Concurrent scanning")
        expectation.expectedFulfillmentCount = 3
        
        // Create multiple concurrent scanning operations
        let scanningOperations = (0..<3).map { index in
            sut.startScanning()
                .prefix(50)
                .collect()
                .sink(receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Scanning operation \(index) failed with error: \(error)")
                    }
                }, receiveValue: { spatialDataArray in
                    // Verify data consistency
                    XCTAssertFalse(spatialDataArray.isEmpty)
                    XCTAssertTrue(spatialDataArray.allSatisfy { $0.confidence >= 0.85 })
                    expectation.fulfill()
                })
        }
        
        // Store cancellables
        scanningOperations.forEach { $0.store(in: &cancellables) }
        
        wait(for: [expectation], timeout: 15.0)
    }
    
    // MARK: - Helper Methods
    
    private func calculateVariance(_ values: [Float]) -> Double {
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        return Double(squaredDifferences.reduce(0, +) / Float(values.count))
    }
}