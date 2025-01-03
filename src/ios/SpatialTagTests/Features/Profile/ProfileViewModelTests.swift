// XCTest - iOS 15.0+ - Testing framework
import XCTest
// Combine - iOS 15.0+ - Async testing support
import Combine

@testable import SpatialTag

// MARK: - Test Constants

private let TEST_PROFILE_ID = UUID()
private let TEST_DISPLAY_NAME = "Test User"
private let TEST_INITIAL_POINTS = 100
private let ELITE_THRESHOLD = 500
private let RARE_THRESHOLD = 1000
private let TEST_TIMEOUT: TimeInterval = 2.0

// MARK: - Mock User Service

final class MockUserService: UserService {
    private var profiles: [UUID: Profile] = [:]
    private var updateCallback: ((Profile) -> Void)?
    private var mockError: Error?
    
    func setMockError(_ error: Error?) {
        mockError = error
    }
    
    func setUpdateCallback(_ callback: @escaping (Profile) -> Void) {
        updateCallback = callback
    }
    
    override func updateUserProfile(_ profile: Profile) -> AnyPublisher<Profile, Error> {
        if let error = mockError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        profiles[profile.id] = profile
        updateCallback?(profile)
        return Just(profile)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    override func updateUserStatus(_ userId: UUID, points: Int) -> AnyPublisher<StatusLevel, Error> {
        if let error = mockError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        let status = StatusLevel.fromPoints(points)
        return Just(status)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    override func updateUserPreferences(_ userId: UUID, preferences: [String: Any]) -> AnyPublisher<Void, Error> {
        if let error = mockError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        if var profile = profiles[userId] {
            _ = profile.updatePreferences(preferences)
            profiles[userId] = profile
        }
        
        return Just(())
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

// MARK: - Profile View Model Tests

@MainActor
final class ProfileViewModelTests: XCTestCase {
    // MARK: - Properties
    
    private var sut: ProfileViewModel!
    private var mockProfile: Profile!
    private var mockUserService: MockUserService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize test profile
        mockProfile = Profile(id: TEST_PROFILE_ID, displayName: TEST_DISPLAY_NAME)
        mockProfile.addPoints(TEST_INITIAL_POINTS)
        
        // Initialize mock service
        mockUserService = MockUserService()
        
        // Initialize system under test
        sut = ProfileViewModel(profile: mockProfile, userService: mockUserService)
        
        // Initialize cancellables set
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        sut = nil
        mockProfile = nil
        mockUserService = nil
        try await super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        // Test initial profile properties
        XCTAssertEqual(sut.profile.id, TEST_PROFILE_ID)
        XCTAssertEqual(sut.displayName, TEST_DISPLAY_NAME)
        XCTAssertEqual(sut.profile.points, TEST_INITIAL_POINTS)
        XCTAssertEqual(sut.profile.statusLevel, .regular)
        XCTAssertFalse(sut.isEditing)
        XCTAssertTrue(sut.isVisible)
        XCTAssertNil(sut.error)
    }
    
    // MARK: - Profile Update Tests
    
    func testProfileUpdateSuccess() async {
        let expectation = expectation(description: "Profile update")
        let newDisplayName = "Updated User"
        
        // Setup update callback
        mockUserService.setUpdateCallback { profile in
            XCTAssertEqual(profile.displayName, newDisplayName)
            expectation.fulfill()
        }
        
        // Update profile
        sut.displayName = newDisplayName
        sut.isVisible = false
        
        let updateResult = await sut.updateProfile()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Update failed with error: \(error)")
                    }
                },
                receiveValue: { _ in }
            )
        
        await waitForExpectations(timeout: TEST_TIMEOUT)
        
        // Verify state updates
        XCTAssertEqual(sut.displayName, newDisplayName)
        XCTAssertFalse(sut.isVisible)
        XCTAssertNil(sut.error)
        
        updateResult.cancel()
    }
    
    func testProfileUpdateFailure() async {
        let expectation = expectation(description: "Profile update failure")
        let mockError = NSError(domain: "test", code: -1, userInfo: nil)
        
        // Setup mock error
        mockUserService.setMockError(mockError)
        
        // Attempt update
        sut.displayName = "Failed Update"
        
        let updateResult = await sut.updateProfile()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual((error as NSError).domain, mockError.domain)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Update should not succeed")
                }
            )
        
        await waitForExpectations(timeout: TEST_TIMEOUT)
        
        // Verify error state
        XCTAssertNotNil(sut.error)
        
        updateResult.cancel()
    }
    
    // MARK: - Status Level Tests
    
    func testStatusLevelTransitions() async {
        let expectation = expectation(description: "Status transitions")
        expectation.expectedFulfillmentCount = 2
        
        var statusUpdates: [StatusLevel] = []
        
        // Monitor status updates
        sut.statusPublisher
            .sink { status in
                statusUpdates.append(status)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger Elite status
        _ = mockProfile.addPoints(ELITE_THRESHOLD - TEST_INITIAL_POINTS)
        XCTAssertEqual(mockProfile.statusLevel, .elite)
        
        // Trigger Rare status
        _ = mockProfile.addPoints(RARE_THRESHOLD - ELITE_THRESHOLD)
        XCTAssertEqual(mockProfile.statusLevel, .rare)
        
        await waitForExpectations(timeout: TEST_TIMEOUT)
        
        // Verify status transitions
        XCTAssertEqual(statusUpdates, [.elite, .rare])
    }
    
    // MARK: - Visibility Tests
    
    func testVisibilityToggle() async {
        let expectation = expectation(description: "Visibility toggle")
        
        // Setup update callback
        mockUserService.setUpdateCallback { profile in
            XCTAssertFalse(profile.isVisible)
            expectation.fulfill()
        }
        
        // Toggle visibility
        await sut.toggleVisibility()
        
        await waitForExpectations(timeout: TEST_TIMEOUT)
        
        // Verify visibility state
        XCTAssertFalse(sut.isVisible)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandlingAndRecovery() async {
        let expectation = expectation(description: "Error handling")
        let mockError = NSError(domain: "test", code: -1, userInfo: nil)
        
        // Monitor error publisher
        sut.errorPublisher
            .sink { error in
                XCTAssertEqual((error as NSError).domain, mockError.domain)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger error
        mockUserService.setMockError(mockError)
        await sut.updateProfile()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        
        await waitForExpectations(timeout: TEST_TIMEOUT)
        
        // Test error recovery
        mockUserService.setMockError(nil)
        sut.clearError()
        XCTAssertNil(sut.error)
    }
    
    // MARK: - Memory Management Tests
    
    func testProperResourceCleanup() async {
        // Setup subscriptions
        let subscription = sut.statusPublisher
            .sink { _ in }
        
        // Trigger cleanup
        await sut.onDisappear()
        
        // Verify cleanup
        XCTAssertTrue(subscription.cancelled)
        XCTAssertTrue(sut.cancellables.isEmpty)
    }
}