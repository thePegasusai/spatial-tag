// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine
// LocalAuthentication - iOS 15.0+ - Device authentication
import LocalAuthentication
// CryptoKit - iOS 15.0+ - Security utilities
import CryptoKit

// Internal imports
import AuthService

/// Validation states for input fields
private enum ValidationState {
    case initial
    case valid
    case invalid(String)
}

/// Signup-specific errors
private enum SignupError: LocalizedError {
    case invalidEmail
    case invalidPassword
    case passwordMismatch
    case invalidDisplayName
    case deviceIntegrityFailed
    case rateLimitExceeded
    case networkError
    case serverError
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address"
        case .invalidPassword:
            return "Password must be at least 8 characters with numbers and special characters"
        case .passwordMismatch:
            return "Passwords do not match"
        case .invalidDisplayName:
            return "Display name must be between 3 and 30 characters"
        case .deviceIntegrityFailed:
            return "Device security check failed"
        case .rateLimitExceeded:
            return "Too many signup attempts. Please try again later"
        case .networkError:
            return "Network connection error. Please check your connection"
        case .serverError:
            return "Server error. Please try again later"
        }
    }
}

/// ViewModel managing secure user registration flow
@MainActor
public final class SignupViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var email: String = ""
    @Published private(set) var password: String = ""
    @Published private(set) var confirmPassword: String = ""
    @Published private(set) var displayName: String = ""
    @Published private(set) var isValid: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: SignupError?
    @Published private(set) var emailValidation: ValidationState = .initial
    @Published private(set) var passwordValidation: ValidationState = .initial
    @Published private(set) var displayNameValidation: ValidationState = .initial
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var signupAttempts: Int = 0
    private let maxSignupAttempts = 5
    private let signupCooldown: TimeInterval = 300 // 5 minutes
    private var lastSignupAttempt: Date?
    
    // MARK: - Initialization
    
    public init() {
        setupValidation()
    }
    
    // MARK: - Public Methods
    
    /// Updates email input with validation
    public func updateEmail(_ newEmail: String) {
        email = sanitizeInput(newEmail)
        emailValidation = validateEmail(email)
        updateFormValidity()
    }
    
    /// Updates password input with validation
    public func updatePassword(_ newPassword: String) {
        password = newPassword
        passwordValidation = validatePassword(password)
        updateFormValidity()
    }
    
    /// Updates confirm password input with validation
    public func updateConfirmPassword(_ newConfirmPassword: String) {
        confirmPassword = newConfirmPassword
        updateFormValidity()
    }
    
    /// Updates display name input with validation
    public func updateDisplayName(_ newDisplayName: String) {
        displayName = sanitizeInput(newDisplayName)
        displayNameValidation = validateDisplayName(displayName)
        updateFormValidity()
    }
    
    /// Attempts to register a new user with validated credentials
    public func signup() -> AnyPublisher<User, SignupError> {
        guard checkRateLimit() else {
            return Fail(error: .rateLimitExceeded).eraseToAnyPublisher()
        }
        
        isLoading = true
        signupAttempts += 1
        lastSignupAttempt = Date()
        
        return AuthService.shared.validateDeviceIntegrity()
            .flatMap { [weak self] isValid -> AnyPublisher<User, Error> in
                guard let self = self else {
                    return Fail(error: SignupError.serverError).eraseToAnyPublisher()
                }
                
                guard isValid else {
                    return Fail(error: SignupError.deviceIntegrityFailed).eraseToAnyPublisher()
                }
                
                let hashedPassword = self.hashPassword(self.password)
                
                let profile = UserProfile(
                    displayName: self.displayName,
                    status: "active",
                    points: 0,
                    level: "basic"
                )
                
                return AuthService.shared.register(
                    email: self.email,
                    password: hashedPassword,
                    profile: profile
                )
            }
            .mapError { error -> SignupError in
                Logger.shared.error("Signup failed: \(error.localizedDescription)", category: "Auth")
                return self.handleSignupError(error)
            }
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupValidation() {
        // Combine validation publishers
        Publishers.CombineLatest4(
            $email,
            $password,
            $confirmPassword,
            $displayName
        )
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.updateFormValidity()
        }
        .store(in: &cancellables)
    }
    
    private func updateFormValidity() {
        isValid = emailValidation == .valid &&
                 passwordValidation == .valid &&
                 displayNameValidation == .valid &&
                 password == confirmPassword &&
                 !password.isEmpty
    }
    
    private func validateEmail(_ email: String) -> ValidationState {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email) ? .valid : .invalid("Invalid email format")
    }
    
    private func validatePassword(_ password: String) -> ValidationState {
        let hasMinLength = password.count >= 8
        let hasNumber = password.range(of: "\\d", options: .regularExpression) != nil
        let hasSpecialChar = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        
        guard hasMinLength else {
            return .invalid("Password must be at least 8 characters")
        }
        guard hasNumber else {
            return .invalid("Password must contain at least one number")
        }
        guard hasSpecialChar else {
            return .invalid("Password must contain at least one special character")
        }
        
        return .valid
    }
    
    private func validateDisplayName(_ name: String) -> ValidationState {
        guard name.count >= 3 && name.count <= 30 else {
            return .invalid("Display name must be between 3 and 30 characters")
        }
        return .valid
    }
    
    private func sanitizeInput(_ input: String) -> String {
        // Remove any potential injection characters
        return input.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func hashPassword(_ password: String) -> String {
        let salt = UUID().uuidString
        let saltedPassword = password + salt
        let hashedData = SHA512.hash(data: saltedPassword.data(using: .utf8)!)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined() + ":" + salt
    }
    
    private func checkRateLimit() -> Bool {
        if let lastAttempt = lastSignupAttempt,
           Date().timeIntervalSince(lastAttempt) < signupCooldown {
            return false
        }
        return signupAttempts < maxSignupAttempts
    }
    
    private func handleSignupError(_ error: Error) -> SignupError {
        if let apiError = error as? APIError {
            switch apiError {
            case .networkError:
                return .networkError
            case .rateLimitExceeded:
                return .rateLimitExceeded
            case .serverError, .serviceUnavailable:
                return .serverError
            default:
                return .serverError
            }
        }
        return .serverError
    }
}