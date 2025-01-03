// XCTest - iOS 15.0+ - Unit testing framework
import XCTest
// Combine - iOS 15.0+ - Async request handling
import Combine
@testable import SpatialTag

/// Comprehensive test suite for TagService functionality
@available(iOS 15.0, *)
final class TagServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: TagService!
    private var cancellables: Set<AnyCancellable>!
    private let testQueue = DispatchQueue(label: "com.spatialtag.tests.tag", qos: .userInitiated)
    
    // Test constants
    private let testTimeout: TimeInterval = 5.0
    private let performanceThreshold: TimeInterval = 0.1 // 100ms requirement
    private let testLocation = Location(
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        altitude: 0,
        spatialCoordinate: simd_float3(x: 1.0, y: 1.0, z: 1.0)
    )
    private let testContent = "Test Tag Content"
    private let testRadius = 50.0
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        sut = TagService.shared
        cancellables = Set<AnyCancellable>()
        
        // Configure performance metrics
        let metrics = XCTMeasureOptions()
        metrics.iterationCount = 10
    }
    
    override func tearDown() async throws {
        // Cancel all subscriptions
        cancellables.removeAll()
        
        // Clean up test data
        try await cleanupTestTags()
        
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Tag Creation Tests
    
    func testCreateTagPerformance() throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "Tag creation")
            
            sut.createTag(
                location: testLocation,
                content: testContent,
                visibilityRadius: testRadius
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        XCTFail("Tag creation failed: \(error)")
                    }
                    expectation.fulfill()
                },
                receiveValue: { tag in
                    // Verify tag properties
                    XCTAssertNotNil(tag.id)
                    XCTAssertEqual(tag.content, self.testContent)
                    XCTAssertEqual(tag.visibilityRadius, self.testRadius)
                    XCTAssertFalse(tag.isExpired())
                    
                    // Verify location precision
                    XCTAssertEqual(tag.location.coordinate.latitude, self.testLocation.coordinate.latitude, accuracy: 0.0001)
                    XCTAssertEqual(tag.location.coordinate.longitude, self.testLocation.coordinate.longitude, accuracy: 0.0001)
                }
            )
            .store(in: &cancellables)
            
            wait(for: [expectation], timeout: testTimeout)
        }
    }
    
    func testConcurrentTagCreation() throws {
        let operationCount = 10
        let expectations = (0..<operationCount).map { index in
            expectation(description: "Concurrent tag creation \(index)")
        }
        
        let startTime = DispatchTime.now()
        
        for i in 0..<operationCount {
            let content = "\(testContent) \(i)"
            sut.createTag(
                location: testLocation,
                content: content
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        expectations[i].fulfill()
                    case .failure(let error):
                        XCTFail("Concurrent tag creation failed: \(error)")
                    }
                },
                receiveValue: { tag in
                    XCTAssertNotNil(tag.id)
                    XCTAssertEqual(tag.content, content)
                }
            )
            .store(in: &cancellables)
        }
        
        wait(for: expectations, timeout: testTimeout)
        
        let endTime = DispatchTime.now()
        let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        
        // Verify performance meets requirements
        XCTAssertLessThan(duration / Double(operationCount), performanceThreshold)
    }
    
    // MARK: - Nearby Tags Tests
    
    func testGetNearbyTagsConcurrency() throws {
        let operationCount = 10
        let expectations = (0..<operationCount).map { index in
            expectation(description: "Nearby tags retrieval \(index)")
        }
        
        // Create test tags first
        try createTestTags(count: operationCount)
        
        // Perform concurrent retrievals
        for i in 0..<operationCount {
            testQueue.async {
                self.sut.getNearbyTags(
                    location: self.testLocation,
                    radius: self.testRadius
                )
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            expectations[i].fulfill()
                        case .failure(let error):
                            XCTFail("Nearby tags retrieval failed: \(error)")
                        }
                    },
                    receiveValue: { tags in
                        XCTAssertFalse(tags.isEmpty)
                        XCTAssertTrue(tags.allSatisfy { !$0.isExpired() })
                        
                        // Verify spatial accuracy
                        for tag in tags {
                            let distance = tag.location.distanceTo(self.testLocation)
                            XCTAssertLessThanOrEqual(try XCTUnwrap(distance.get()), self.testRadius)
                        }
                    }
                )
                .store(in: &self.cancellables)
            }
        }
        
        wait(for: expectations, timeout: testTimeout)
    }
    
    // MARK: - LiDAR Precision Tests
    
    func testLiDARPrecision() throws {
        let expectation = expectation(description: "LiDAR precision validation")
        
        sut.validateLiDARPrecision(location: testLocation)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("LiDAR precision validation failed: \(error)")
                    }
                },
                receiveValue: { isValid in
                    XCTAssertTrue(isValid, "LiDAR precision should meet requirements")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Helper Methods
    
    private func createTestTags(count: Int) throws {
        let group = DispatchGroup()
        
        for i in 0..<count {
            group.enter()
            
            sut.createTag(
                location: testLocation,
                content: "\(testContent) \(i)"
            )
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        group.leave()
                    case .failure(let error):
                        XCTFail("Test tag creation failed: \(error)")
                        group.leave()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        }
        
        let result = group.wait(timeout: .now() + testTimeout)
        XCTAssertEqual(result, .success)
    }
    
    private func cleanupTestTags() async throws {
        let expectation = expectation(description: "Cleanup test tags")
        
        sut.getNearbyTags(location: testLocation, radius: testRadius)
            .flatMap { tags -> AnyPublisher<Void, Error> in
                let deletions = tags.map { self.sut.deleteTag(id: $0.id) }
                return Publishers.MergeMany(deletions)
                    .collect()
                    .map { _ in }
                    .eraseToAnyPublisher()
            }
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("Cleanup failed: \(error)")
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: testTimeout)
    }
}