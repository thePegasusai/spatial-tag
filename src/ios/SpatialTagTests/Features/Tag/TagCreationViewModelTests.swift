// XCTest - iOS 15.0+ - Testing framework
import XCTest
// Combine - iOS 15.0+ - Async testing
import Combine
@testable import SpatialTag

final class TagCreationViewModelTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: TagCreationViewModel!
    private var mockTagService: MockTagService!
    private var mockLocationManager: MockLocationManager!
    private var mockARSceneManager: MockARSceneManager!
    private var cancellables: Set<AnyCancellable>!
    private var performanceMetrics: PerformanceMetrics!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        mockTagService = MockTagService()
        mockLocationManager = MockLocationManager()
        mockARSceneManager = MockARSceneManager()
        cancellables = Set<AnyCancellable>()
        performanceMetrics = PerformanceMetrics()
        
        sut = TagCreationViewModel(
            tagService: mockTagService,
            locationManager: mockLocationManager,
            arSceneManager: mockARSceneManager
        )
    }
    
    override func tearDown() {
        sut = nil
        mockTagService = nil
        mockLocationManager = nil
        mockARSceneManager = nil
        cancellables = nil
        performanceMetrics = nil
        super.tearDown()
    }
    
    // MARK: - Input Validation Tests
    
    func testTitleValidation() {
        // Test empty title
        sut.title = ""
        XCTAssertFalse(sut.isValid)
        
        // Test title within limits
        sut.title = "Valid Tag Title"
        sut.description = "Valid description"
        sut.visibilityRadius = 25.0
        sut.duration = 12.0
        XCTAssertTrue(sut.isValid)
        
        // Test title exceeding max length (50 characters)
        sut.title = String(repeating: "a", count: 51)
        XCTAssertFalse(sut.isValid)
    }
    
    func testDescriptionValidation() {
        sut.title = "Valid Title"
        
        // Test description within limits
        sut.description = "Valid description"
        sut.visibilityRadius = 25.0
        sut.duration = 12.0
        XCTAssertTrue(sut.isValid)
        
        // Test description exceeding max length (200 characters)
        sut.description = String(repeating: "a", count: 201)
        XCTAssertFalse(sut.isValid)
    }
    
    func testVisibilityRadiusValidation() {
        sut.title = "Valid Title"
        sut.description = "Valid description"
        sut.duration = 12.0
        
        // Test minimum radius
        sut.visibilityRadius = 0.4 // Below 0.5m minimum
        XCTAssertFalse(sut.isValid)
        
        // Test valid radius
        sut.visibilityRadius = 25.0
        XCTAssertTrue(sut.isValid)
        
        // Test maximum radius
        sut.visibilityRadius = 51.0 // Above 50m maximum
        XCTAssertFalse(sut.isValid)
    }
    
    func testDurationValidation() {
        sut.title = "Valid Title"
        sut.description = "Valid description"
        sut.visibilityRadius = 25.0
        
        // Test minimum duration
        sut.duration = 0.5 // Below 1 hour minimum
        XCTAssertFalse(sut.isValid)
        
        // Test valid duration
        sut.duration = 12.0
        XCTAssertTrue(sut.isValid)
        
        // Test maximum duration
        sut.duration = 25.0 // Above 24 hours maximum
        XCTAssertFalse(sut.isValid)
    }
    
    // MARK: - LiDAR Precision Tests
    
    func testLiDARPrecision() {
        let expectation = XCTestExpectation(description: "LiDAR precision validation")
        
        // Configure mock AR scene with known precision
        mockARSceneManager.simulatedPrecision = 0.009 // Within ±1cm threshold
        
        sut.title = "Valid Title"
        sut.description = "Valid description"
        sut.visibilityRadius = 25.0
        sut.duration = 12.0
        
        // Attempt tag creation
        sut.createTag()
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        expectation.fulfill()
                    case .failure(let error):
                        XCTFail("Tag creation failed: \(error)")
                    }
                },
                receiveValue: { success in
                    XCTAssertTrue(success)
                    XCTAssertLessThanOrEqual(self.mockARSceneManager.simulatedPrecision, 0.01)
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testLiDARPrecisionFailure() {
        let expectation = XCTestExpectation(description: "LiDAR precision failure")
        
        // Configure mock AR scene with insufficient precision
        mockARSceneManager.simulatedPrecision = 0.02 // Above ±1cm threshold
        
        sut.title = "Valid Title"
        sut.description = "Valid description"
        sut.visibilityRadius = 25.0
        sut.duration = 12.0
        
        sut.createTag()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error as? ARError, ARError.precisionNotMet)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Tag creation should fail with insufficient precision")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Performance Tests
    
    func testBatteryImpact() {
        // Configure initial battery impact
        mockARSceneManager.simulatedBatteryImpact = 0.05 // 5% impact
        
        // Verify battery impact is within threshold
        XCTAssertLessThanOrEqual(sut.batteryImpact, 0.15)
        
        // Simulate high battery impact
        mockARSceneManager.simulatedBatteryImpact = 0.20 // 20% impact
        XCTAssertFalse(sut.isValid) // Should invalidate due to high battery impact
    }
    
    func testRefreshRate() {
        // Configure mock AR scene
        mockARSceneManager.simulatedRefreshRate = 60.0 // 60Hz
        
        // Verify refresh rate meets minimum requirement
        XCTAssertGreaterThanOrEqual(mockARSceneManager.simulatedRefreshRate, 30.0)
        
        // Test low refresh rate
        mockARSceneManager.simulatedRefreshRate = 25.0 // Below 30Hz minimum
        XCTAssertFalse(sut.isValid) // Should invalidate due to low refresh rate
    }
    
    // MARK: - Concurrent Operation Tests
    
    func testConcurrentTagCreation() {
        let expectation = XCTestExpectation(description: "Concurrent tag creation")
        expectation.expectedFulfillmentCount = 3
        
        let validInput = {
            self.sut.title = "Valid Title"
            self.sut.description = "Valid description"
            self.sut.visibilityRadius = 25.0
            self.sut.duration = 12.0
        }
        
        // Create multiple concurrent tag operations
        for i in 0..<3 {
            validInput()
            sut.createTag()
                .sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            expectation.fulfill()
                        case .failure(let error):
                            XCTFail("Tag creation \(i) failed: \(error)")
                        }
                    },
                    receiveValue: { success in
                        XCTAssertTrue(success)
                    }
                )
                .store(in: &cancellables)
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Helper Types
    
    private struct PerformanceMetrics {
        var processingTime: TimeInterval = 0
        var batteryImpact: Double = 0
        var memoryUsage: UInt64 = 0
    }
}

// MARK: - Mock Services

private class MockTagService: TagService {
    var createTagCallCount = 0
    var validatePlacementCallCount = 0
    
    override func createTag(location: Location, content: String, visibilityRadius: Double?, expirationHours: TimeInterval?) -> AnyPublisher<Tag, Error> {
        createTagCallCount += 1
        return Just(Tag(id: UUID(), creatorId: UUID(), location: location, content: content))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

private class MockLocationManager: LocationManager {
    var simulatedLocation: Location?
    
    override func startUpdatingLocation() -> AnyPublisher<Location, LocationError> {
        if let location = simulatedLocation {
            return Just(location)
                .setFailureType(to: LocationError.self)
                .eraseToAnyPublisher()
        }
        return Fail(error: LocationError.invalidLocation).eraseToAnyPublisher()
    }
}

private class MockARSceneManager: ARSceneManager {
    var simulatedPrecision: Double = 0.01
    var simulatedBatteryImpact: Double = 0.05
    var simulatedRefreshRate: Double = 60.0
    
    override func validatePrecision() -> AnyPublisher<Double, Error> {
        return Just(simulatedPrecision)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}