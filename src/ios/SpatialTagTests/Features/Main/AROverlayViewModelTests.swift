// XCTest - iOS testing framework (latest)
import XCTest
// Combine - iOS 15.0+ - Async testing support
import Combine
// ARKit - 6.0 - AR functionality testing
import ARKit
@testable import SpatialTag

final class AROverlayViewModelTests: XCTestCase {
    // MARK: - Properties
    
    private var sut: AROverlayViewModel!
    private var mockSceneManager: MockARSceneManager!
    private var mockLidarProcessor: MockLiDARProcessor!
    private var mockTagService: MockTagService!
    private var cancellables: Set<AnyCancellable>!
    private var performanceMonitor: PerformanceMetrics!
    private var threadValidator: ThreadSafetyValidator!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        mockSceneManager = MockARSceneManager()
        mockLidarProcessor = MockLiDARProcessor()
        mockTagService = MockTagService()
        cancellables = Set<AnyCancellable>()
        performanceMonitor = PerformanceMetrics(frameRate: 0, processingTime: 0, batteryImpact: 0, memoryUsage: 0)
        threadValidator = ThreadSafetyValidator()
        
        sut = AROverlayViewModel(
            sceneManager: mockSceneManager,
            lidarProcessor: mockLidarProcessor,
            tagService: mockTagService
        )
    }
    
    override func tearDown() {
        sut = nil
        mockSceneManager = nil
        mockLidarProcessor = nil
        mockTagService = nil
        cancellables = nil
        performanceMonitor = nil
        threadValidator = nil
        super.tearDown()
    }
    
    // MARK: - AR Session Tests
    
    func testStartARSession() async {
        // Given
        let expectation = expectation(description: "AR session started")
        let startTime = CACurrentMediaTime()
        
        // When
        await sut.startARSession()
        
        // Then
        XCTAssertTrue(sut.isScanning)
        XCTAssertEqual(sut.overlayState, .ready)
        
        // Verify scene manager interaction
        XCTAssertTrue(mockSceneManager.startSceneCalled)
        
        // Verify LiDAR processor interaction
        XCTAssertTrue(mockLidarProcessor.startScanningCalled)
        
        // Verify performance
        let processingTime = CACurrentMediaTime() - startTime
        XCTAssertLessThan(processingTime, TEST_PERFORMANCE_THRESHOLD_MS / 1000)
        
        // Verify memory usage
        let memoryUsage = ProcessInfo.processInfo.physicalMemory / 1024 / 1024 // Convert to MB
        XCTAssertLessThan(memoryUsage, TEST_MEMORY_THRESHOLD_MB)
        
        expectation.fulfill()
        await waitForExpectations(timeout: 5)
    }
    
    func testStopARSession() async {
        // Given
        await sut.startARSession()
        
        // When
        sut.stopARSession()
        
        // Then
        XCTAssertFalse(sut.isScanning)
        XCTAssertEqual(sut.overlayState, .initializing)
        XCTAssertTrue(mockSceneManager.stopSceneCalled)
        XCTAssertTrue(mockLidarProcessor.stopScanningCalled)
        XCTAssertTrue(sut.visibleTags.isEmpty)
    }
    
    // MARK: - Tag Interaction Tests
    
    func testHandleTagInteraction() async {
        // Given
        let tagId = UUID()
        let tag = Tag(id: tagId, creatorId: UUID(), location: Location(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)), content: "Test Tag")
        mockTagService.mockTags = [tag]
        
        // When
        await sut.handleTagInteraction(tagId)
        
        // Then
        XCTAssertTrue(mockTagService.interactWithTagCalled)
        XCTAssertEqual(mockTagService.lastInteractedTagId, tagId)
    }
    
    func testHandleTagInteractionWithError() async {
        // Given
        let tagId = UUID()
        mockTagService.shouldSimulateError = true
        
        // When
        await sut.handleTagInteraction(tagId)
        
        // Then
        XCTAssertEqual(sut.overlayState, .error("Tag interaction failed"))
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceUnderLoad() async {
        // Given
        let tagCount = TEST_MAX_VISIBLE_TAGS
        var tags: [Tag] = []
        for _ in 0..<tagCount {
            let tag = Tag(id: UUID(), creatorId: UUID(), location: Location(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)), content: "Test Tag")
            tags.append(tag)
        }
        mockTagService.mockTags = tags
        
        let startTime = CACurrentMediaTime()
        
        // When
        await sut.startARSession()
        
        // Then
        let processingTime = CACurrentMediaTime() - startTime
        XCTAssertLessThan(processingTime, TEST_PERFORMANCE_THRESHOLD_MS / 1000)
        
        let memoryUsage = ProcessInfo.processInfo.physicalMemory / 1024 / 1024
        XCTAssertLessThan(memoryUsage, TEST_MEMORY_THRESHOLD_MB)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentTagOperations() async {
        // Given
        let operationCount = 100
        let expectation = expectation(description: "Concurrent operations completed")
        expectation.expectedFulfillmentCount = operationCount
        
        // When
        for _ in 0..<operationCount {
            Task {
                let tagId = UUID()
                await sut.handleTagInteraction(tagId)
                expectation.fulfill()
            }
        }
        
        // Then
        await waitForExpectations(timeout: 10)
        XCTAssertEqual(sut.overlayState, .ready)
    }
    
    // MARK: - Error Recovery Tests
    
    func testErrorRecovery() async {
        // Given
        mockLidarProcessor.shouldSimulateError = true
        let expectation = expectation(description: "Error recovery completed")
        
        // When
        await sut.startARSession()
        
        // Then
        XCTAssertEqual(sut.overlayState, .error("LiDAR initialization failed"))
        
        // Simulate recovery
        mockLidarProcessor.shouldSimulateError = false
        await sut.startARSession()
        
        XCTAssertEqual(sut.overlayState, .ready)
        expectation.fulfill()
        
        await waitForExpectations(timeout: 5)
    }
}

// MARK: - Mock Classes

private class MockARSceneManager: ARSceneManager {
    var startSceneCalled = false
    var stopSceneCalled = false
    
    override func startScene() -> AnyPublisher<ARUpdate, Error> {
        startSceneCalled = true
        return Just(ARUpdate(frame: ARFrame(), tags: [:], performance: PerformanceMetrics(frameRate: 60, processingTime: 0.016, batteryImpact: 0.1, memoryUsage: 100)))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    override func stopScene() {
        stopSceneCalled = true
    }
}

private class MockLiDARProcessor: LiDARProcessor {
    var startScanningCalled = false
    var stopScanningCalled = false
    var shouldSimulateError = false
    
    override func startScanning() -> AnyPublisher<SpatialData, Error> {
        startScanningCalled = true
        if shouldSimulateError {
            return Fail(error: LiDARError.sessionConfigurationFailed)
                .eraseToAnyPublisher()
        }
        return Just(SpatialData(pointCloud: ARPointCloud(points: [], confidenceValues: []), confidence: 1.0, timestamp: 0, powerUsage: 0.1, processingTime: 0.016))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    override func stopScanning() {
        stopScanningCalled = true
    }
}

private class MockTagService: TagService {
    var mockTags: [Tag] = []
    var interactWithTagCalled = false
    var lastInteractedTagId: UUID?
    var shouldSimulateError = false
    
    override func getNearbyTags(location: Location) -> AnyPublisher<[Tag], Error> {
        return Just(mockTags)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    override func interactWithTag(_ tagId: UUID) async throws {
        interactWithTagCalled = true
        lastInteractedTagId = tagId
        if shouldSimulateError {
            throw TagError.invalidContent
        }
    }
}

private class ThreadSafetyValidator {
    private let queue = DispatchQueue(label: "com.spatialtag.threadsafety")
    private var operations: [UUID: Date] = [:]
    
    func validateOperation(_ id: UUID) {
        queue.sync {
            operations[id] = Date()
        }
    }
}