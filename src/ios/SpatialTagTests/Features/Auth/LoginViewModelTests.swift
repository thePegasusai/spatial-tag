// XCTest - iOS 15.0+ - Unit testing framework
import XCTest
// Combine - iOS 15.0+ - Asynchronous testing support
import Combine

@testable import SpatialTag

@available(iOS 15.0, *)
final class LoginViewModelTests: XCTestCase {
    // MARK: - Properties
    
    private var sut: LoginViewModel!
    private var mockAuthService: MockAuthService!
    private var mockBiometricAuth: MockBiometricAuthenticator!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        mockAuthService = MockAuthService()
        mockBiometricAuth = MockBiometricAuthenticator()
        sut = LoginViewModel(authService: mockAuthService, biometricAuth: mockBiometricAuth)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockAuthService = nil
        mockBiometricAuth = nil
        super.tearDown()
    }
    
    // MARK: - Email/Password Authentication Tests
    
    func testLoginSuccess() async throws {
        // Given
        let expectation = expectation(description: "Login success")
        mockAuthService.loginResult = .success(User.mock())
        
        // When
        sut.updateEmail(TEST_EMAIL)
        sut.updatePassword(TEST_PASSWORD)
        
        var loadingStates: [Bool] = []
        var error: Error?
        var completed = false
        
        sut.$isLoading
            .sink { loadingStates.append($0) }
            .store(in: &cancellables)
        
        sut.$error
            .sink { error = $0 }
            .store(in: &cancellables)
        
        // Then
        sut.login()
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        completed = true
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: TEST_TIMEOUT)
        
        XCTAssertTrue(completed)
        XCTAssertNil(error)
        XCTAssertEqual(loadingStates, [false, true, false])
        XCTAssertEqual(mockAuthService.loginCallCount, 1)
        XCTAssertEqual(mockAuthService.lastEmail, TEST_EMAIL)
        XCTAssertEqual(mockAuthService.lastPassword, TEST_PASSWORD)
    }
    
    func testLoginFailure() async throws {
        // Given
        let expectation = expectation(description: "Login failure")
        let expectedError = AuthError.invalidCredentials
        mockAuthService.loginResult = .failure(expectedError)
        
        // When
        sut.updateEmail(TEST_EMAIL)
        sut.updatePassword(TEST_PASSWORD)
        
        var loadingStates: [Bool] = []
        var receivedError: Error?
        
        sut.$isLoading
            .sink { loadingStates.append($0) }
            .store(in: &cancellables)
        
        sut.$error
            .sink { receivedError = $0 }
            .store(in: &cancellables)
        
        // Then
        sut.login()
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: TEST_TIMEOUT)
        
        XCTAssertEqual(loadingStates, [false, true, false])
        XCTAssertEqual(receivedError as? AuthError, expectedError)
        XCTAssertEqual(mockAuthService.loginCallCount, 1)
    }
    
    // MARK: - Biometric Authentication Tests
    
    func testBiometricLoginSuccess() async throws {
        // Given
        let expectation = expectation(description: "Biometric login success")
        mockBiometricAuth.canUseBiometricsResult = true
        mockAuthService.biometricLoginResult = .success(User.mock())
        
        // When
        var loadingStates: [Bool] = []
        var error: Error?
        var completed = false
        
        sut.$isLoading
            .sink { loadingStates.append($0) }
            .store(in: &cancellables)
        
        sut.$error
            .sink { error = $0 }
            .store(in: &cancellables)
        
        // Then
        sut.loginWithBiometrics()
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        completed = true
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: TEST_TIMEOUT)
        
        XCTAssertTrue(completed)
        XCTAssertNil(error)
        XCTAssertEqual(loadingStates, [false, true, false])
        XCTAssertEqual(mockAuthService.biometricLoginCallCount, 1)
    }
    
    // MARK: - Input Validation Tests
    
    func testEmailValidation() {
        // Test invalid email
        sut.updateEmail(TEST_INVALID_EMAIL)
        XCTAssertEqual(sut.emailValidation, .error("Invalid email format"))
        XCTAssertFalse(sut.isLoginEnabled)
        
        // Test valid email
        sut.updateEmail(TEST_EMAIL)
        XCTAssertEqual(sut.emailValidation, .valid)
    }
    
    func testPasswordValidation() {
        // Test weak password
        sut.updatePassword(TEST_WEAK_PASSWORD)
        XCTAssertEqual(sut.passwordValidation, .error("Password must be at least 12 characters"))
        XCTAssertFalse(sut.isLoginEnabled)
        
        // Test valid password
        sut.updatePassword(TEST_PASSWORD)
        XCTAssertEqual(sut.passwordValidation, .valid)
    }
    
    func testLoginButtonEnablement() {
        // Initially disabled
        XCTAssertFalse(sut.isLoginEnabled)
        
        // Valid email, invalid password
        sut.updateEmail(TEST_EMAIL)
        sut.updatePassword(TEST_WEAK_PASSWORD)
        XCTAssertFalse(sut.isLoginEnabled)
        
        // Valid email and password
        sut.updatePassword(TEST_PASSWORD)
        XCTAssertTrue(sut.isLoginEnabled)
    }
    
    // MARK: - Rate Limiting Tests
    
    func testLoginRateLimiting() async throws {
        // Given
        mockAuthService.loginResult = .failure(AuthError.invalidCredentials)
        
        // When - Attempt multiple logins
        for _ in 1...5 {
            let expectation = expectation(description: "Login attempt")
            
            sut.login()
                .sink(
                    receiveCompletion: { _ in expectation.fulfill() },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
            
            await fulfillment(of: [expectation], timeout: TEST_TIMEOUT)
        }
        
        // Then
        XCTAssertEqual(sut.error as? AuthError, .tooManyAttempts)
    }
}

// MARK: - Mock Objects

private class MockAuthService: AuthService {
    var loginCallCount = 0
    var biometricLoginCallCount = 0
    var lastEmail: String?
    var lastPassword: String?
    var loginResult: Result<User, Error> = .failure(AuthError.invalidCredentials)
    var biometricLoginResult: Result<User, Error> = .failure(AuthError.biometricsNotAvailable)
    
    override func login(email: String, password: String) -> AnyPublisher<User, Error> {
        loginCallCount += 1
        lastEmail = email
        lastPassword = password
        return loginResult.publisher.eraseToAnyPublisher()
    }
    
    override func loginWithBiometrics() -> AnyPublisher<User, Error> {
        biometricLoginCallCount += 1
        return biometricLoginResult.publisher.eraseToAnyPublisher()
    }
}

private class MockBiometricAuthenticator: BiometricAuthenticator {
    var canUseBiometricsResult = false
    
    override func canUseBiometrics() -> Bool {
        return canUseBiometricsResult
    }
}

// MARK: - Test Helpers

private extension User {
    static func mock() -> User {
        return User(id: UUID().uuidString, email: TEST_EMAIL, status: "active")
    }
}