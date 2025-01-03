// XCTest - iOS 15.0+ - Unit testing framework
import XCTest
// Combine - iOS 15.0+ - Async request handling
import Combine
// LocalAuthentication - iOS 15.0+ - Biometric authentication
import LocalAuthentication

@testable import SpatialTag

final class AuthServiceTests: XCTestCase {
    // MARK: - Properties
    
    private var sut: AuthService!
    private var mockAPIClient: MockAPIClient!
    private var mockKeychainManager: MockKeychainManager!
    private var mockBiometricContext: MockLAContext!
    private var mockSecurityValidator: MockSecurityValidator!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockKeychainManager = MockKeychainManager()
        mockBiometricContext = MockLAContext()
        mockSecurityValidator = MockSecurityValidator()
        cancellables = Set<AnyCancellable>()
        sut = AuthService.shared
    }
    
    override func tearDown() {
        sut = nil
        mockAPIClient = nil
        mockKeychainManager = nil
        mockBiometricContext = nil
        mockSecurityValidator = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Login Tests
    
    func testLoginWithValidCredentials() {
        // Given
        let expectation = XCTestExpectation(description: "Login success")
        let expectedUser = User(id: "test_id", email: TEST_EMAIL, displayName: TEST_DISPLAY_NAME)
        let authResponse = AuthResponse(user: expectedUser, accessToken: TEST_AUTH_TOKEN, refreshToken: TEST_REFRESH_TOKEN)
        
        mockAPIClient.mockResponse = authResponse
        mockSecurityValidator.deviceIntegrityResult = true
        
        // When
        sut.login(email: TEST_EMAIL, password: TEST_PASSWORD)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Login failed with error: \(error)")
                    }
                },
                receiveValue: { user in
                    // Then
                    XCTAssertEqual(user.id, expectedUser.id)
                    XCTAssertEqual(user.email, expectedUser.email)
                    XCTAssertEqual(user.displayName, expectedUser.displayName)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testLoginWithInvalidCredentials() {
        // Given
        let expectation = XCTestExpectation(description: "Login failure")
        mockAPIClient.mockError = AuthError.unauthorized
        mockSecurityValidator.deviceIntegrityResult = true
        
        // When
        sut.login(email: TEST_EMAIL, password: "wrong_password")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Then
                        XCTAssertEqual(error as? AuthError, .unauthorized)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Login should not succeed")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Biometric Authentication Tests
    
    func testBiometricAuthenticationSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Biometric auth success")
        mockBiometricContext.canEvaluatePolicy = true
        mockBiometricContext.evaluatePolicyResult = true
        mockKeychainManager.mockStoredToken = TEST_AUTH_TOKEN
        
        // When
        sut.loginWithBiometrics()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Biometric auth failed with error: \(error)")
                    }
                },
                receiveValue: { user in
                    // Then
                    XCTAssertNotNil(user)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testBiometricAuthenticationNotAvailable() {
        // Given
        let expectation = XCTestExpectation(description: "Biometric auth failure")
        mockBiometricContext.canEvaluatePolicy = false
        
        // When
        sut.loginWithBiometrics()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Then
                        XCTAssertEqual(error as? AuthError, .biometricsNotAvailable)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Biometric auth should not succeed")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Token Management Tests
    
    func testTokenRefreshSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Token refresh success")
        let newAuthToken = "new_auth_token"
        let newRefreshToken = "new_refresh_token"
        mockKeychainManager.mockStoredToken = TEST_REFRESH_TOKEN
        mockAPIClient.mockResponse = AuthResponse(
            user: User(id: "test_id", email: TEST_EMAIL, displayName: TEST_DISPLAY_NAME),
            accessToken: newAuthToken,
            refreshToken: newRefreshToken
        )
        
        // When
        sut.refreshToken()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Token refresh failed with error: \(error)")
                    }
                },
                receiveValue: { success in
                    // Then
                    XCTAssertTrue(success)
                    XCTAssertEqual(self.mockKeychainManager.lastSavedToken, newAuthToken)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Security Tests
    
    func testDeviceIntegrityValidation() {
        // Given
        let expectation = XCTestExpectation(description: "Device integrity check")
        mockSecurityValidator.deviceIntegrityResult = false
        
        // When
        sut.login(email: TEST_EMAIL, password: TEST_PASSWORD)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Then
                        XCTAssertEqual(error as? AuthError, .deviceIntegrityFailed)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Login should not succeed with failed integrity check")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRateLimitExceeded() {
        // Given
        let expectation = XCTestExpectation(description: "Rate limit check")
        
        // When
        for _ in 0...5 { // Exceed the 5 attempts limit
            sut.login(email: TEST_EMAIL, password: TEST_PASSWORD)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }
        
        // Then
        sut.login(email: TEST_EMAIL, password: TEST_PASSWORD)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error as? AuthError, .tooManyAttempts)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Login should not succeed after rate limit exceeded")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Objects

private class MockAPIClient {
    var mockResponse: Any?
    var mockError: Error?
    
    func request<T: Decodable>(endpoint: APIEndpoint, body: Encodable?) -> AnyPublisher<T, Error> {
        if let error = mockError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        if let response = mockResponse as? T {
            return Just(response)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return Fail(error: AuthError.serviceUnavailable).eraseToAnyPublisher()
    }
}

private class MockKeychainManager {
    var mockStoredToken: String?
    var lastSavedToken: String?
    
    func saveToken(_ token: String, forKey key: String) -> Result<Bool, KeychainError> {
        lastSavedToken = token
        return .success(true)
    }
    
    func retrieveToken(forKey key: String) -> Result<String?, KeychainError> {
        return .success(mockStoredToken)
    }
}

private class MockLAContext {
    var canEvaluatePolicy: Bool = false
    var evaluatePolicyResult: Bool = false
    
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        return canEvaluatePolicy
    }
    
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        reply(evaluatePolicyResult, evaluatePolicyResult ? nil : AuthError.biometricsFailed)
    }
}

private class MockSecurityValidator {
    var deviceIntegrityResult: Bool = true
    
    func validateDeviceIntegrity() -> AnyPublisher<Bool, Error> {
        return Just(deviceIntegrityResult)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}