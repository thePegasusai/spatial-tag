// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

// Internal imports
import ViewModelProtocol
import AuthService
import BiometricAuthenticator

/// Enhanced view model for secure authentication operations
@MainActor
final class LoginViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var email: String = ""
    @Published private(set) var password: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    @Published private(set) var isBiometricsAvailable: Bool = false
    @Published private(set) var isLoginEnabled: Bool = false
    @Published private(set) var emailValidation: ValidationState = .idle
    @Published private(set) var passwordValidation: ValidationState = .idle
    
    // MARK: - Private Properties
    
    private let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
    private let passwordMinLength = 12
    private let maxLoginAttempts = 3
    private let loginTimeoutDuration: TimeInterval = 300.0
    
    private var loginAttempts: Int = 0
    private var lastLoginAttempt: Date?
    private var validationPublishers: Set<AnyCancellable> = []
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupBiometricAvailability()
        setupInputValidation()
        setupRateLimiting()
    }
    
    // MARK: - Public Methods
    
    /// Updates email input with validation
    func updateEmail(_ newEmail: String) {
        email = newEmail
        validateEmail()
    }
    
    /// Updates password input with validation
    func updatePassword(_ newPassword: String) {
        password = newPassword
        validatePassword()
    }
    
    /// Performs secure email/password authentication
    func login() -> AnyPublisher<Void, Error> {
        guard validateRateLimit() else {
            return Fail(error: AuthError.tooManyAttempts).eraseToAnyPublisher()
        }
        
        guard validateInput() else {
            return Fail(error: AuthError.invalidCredentials).eraseToAnyPublisher()
        }
        
        isLoading = true
        error = nil
        
        return AuthService.shared.login(email: email, password: password)
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    self?.loginAttempts += 1
                    self?.lastLoginAttempt = Date()
                },
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveCancel: { [weak self] in
                    self?.isLoading = false
                }
            )
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    /// Performs secure biometric authentication
    func loginWithBiometrics() -> AnyPublisher<Void, Error> {
        guard isBiometricsAvailable else {
            return Fail(error: AuthError.biometricsNotAvailable).eraseToAnyPublisher()
        }
        
        isLoading = true
        error = nil
        
        return AuthService.shared.loginWithBiometrics()
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveCancel: { [weak self] in
                    self?.isLoading = false
                }
            )
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupBiometricAvailability() {
        isBiometricsAvailable = BiometricAuthenticator.shared.canUseBiometrics()
    }
    
    private func setupInputValidation() {
        Publishers.CombineLatest($email, $password)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] email, password in
                self?.validateInput()
            }
            .store(in: &validationPublishers)
    }
    
    private func setupRateLimiting() {
        Timer.publish(every: loginTimeoutDuration, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.resetRateLimit()
            }
            .store(in: &cancellables)
    }
    
    private func validateEmail() -> Bool {
        guard !email.isEmpty else {
            emailValidation = .error("Email is required")
            return false
        }
        
        guard NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email) else {
            emailValidation = .error("Invalid email format")
            return false
        }
        
        emailValidation = .valid
        return true
    }
    
    private func validatePassword() -> Bool {
        guard !password.isEmpty else {
            passwordValidation = .error("Password is required")
            return false
        }
        
        guard password.count >= passwordMinLength else {
            passwordValidation = .error("Password must be at least \(passwordMinLength) characters")
            return false
        }
        
        // Check password complexity
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        let hasSpecialChar = password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) })
        
        guard hasUppercase && hasLowercase && hasNumber && hasSpecialChar else {
            passwordValidation = .error("Password must contain uppercase, lowercase, number, and special character")
            return false
        }
        
        passwordValidation = .valid
        return true
    }
    
    private func validateInput() -> Bool {
        let isEmailValid = validateEmail()
        let isPasswordValid = validatePassword()
        isLoginEnabled = isEmailValid && isPasswordValid
        return isLoginEnabled
    }
    
    private func validateRateLimit() -> Bool {
        if let lastAttempt = lastLoginAttempt,
           Date().timeIntervalSince(lastAttempt) < loginTimeoutDuration {
            return false
        }
        return loginAttempts < maxLoginAttempts
    }
    
    private func resetRateLimit() {
        loginAttempts = 0
        lastLoginAttempt = nil
    }
    
    private func handleError(_ error: Error) {
        self.error = error
        Logger.shared.error("Login error: \(error.localizedDescription)", category: "Auth")
        
        if loginAttempts >= maxLoginAttempts {
            self.error = AuthError.tooManyAttempts
        }
    }
}

// MARK: - Supporting Types

enum ValidationState: Equatable {
    case idle
    case valid
    case error(String)
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case tooManyAttempts
    case biometricsNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .tooManyAttempts:
            return "Too many login attempts. Please try again later"
        case .biometricsNotAvailable:
            return "Biometric authentication is not available"
        }
    }
}