// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Async request handling
import Combine
// LocalAuthentication - iOS 15.0+ - Biometric authentication
import LocalAuthentication
// DeviceCheck - iOS 15.0+ - Device integrity validation
import DeviceCheck
// os.log - iOS 15.0+ - System logging
import os.log

// Internal imports
import APIClient
import KeychainManager
import NetworkMonitor

/// Constants for authentication service
private enum AuthConstants {
    static let AUTH_TOKEN_KEY = "auth_token"
    static let REFRESH_TOKEN_KEY = "refresh_token"
    static let BIOMETRIC_REASON = "Authenticate to access Spatial Tag"
    static let MAX_LOGIN_ATTEMPTS = 5
    static let TOKEN_REFRESH_THRESHOLD: TimeInterval = 300 // 5 minutes
    static let LOGIN_COOLDOWN: TimeInterval = 300 // 5 minutes
}

/// User authentication states
private enum AuthState {
    case authenticated(User)
    case unauthenticated
    case refreshing
    case error(Error)
}

/// Enhanced authentication service with security features
@available(iOS 15.0, *)
public final class AuthService {
    // MARK: - Properties
    
    public static let shared = AuthService()
    
    public let currentUser = CurrentValueSubject<User?, Never>(nil)
    private let authState = CurrentValueSubject<AuthState, Never>(.unauthenticated)
    private let authContext = LAContext()
    private var cancellables = Set<AnyCancellable>()
    private var tokenRefreshTimer: Timer?
    private var loginAttempts = 0
    private var lastLoginAttempt: Date?
    private let deviceCheck = DCDevice.current
    
    // MARK: - Initialization
    
    private init() {
        setupSecurityMonitoring()
        restoreSession()
    }
    
    // MARK: - Public Methods
    
    /// Authenticates user with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    /// - Returns: Publisher emitting authenticated user or error
    public func login(email: String, password: String) -> AnyPublisher<User, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthError.serviceUnavailable))
                return
            }
            
            // Check login rate limiting
            if !self.checkLoginRateLimit() {
                promise(.failure(AuthError.tooManyAttempts))
                return
            }
            
            // Validate device integrity
            self.validateDeviceIntegrity()
                .flatMap { isValid -> AnyPublisher<User, Error> in
                    guard isValid else {
                        return Fail(error: AuthError.deviceIntegrityFailed).eraseToAnyPublisher()
                    }
                    
                    let credentials = ["email": email, "password": password]
                    return APIClient.shared.request(endpoint: .auth(.login), body: credentials)
                }
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            self.handleLoginFailure(error)
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { [weak self] (response: AuthResponse) in
                        self?.handleLoginSuccess(response, promise: promise)
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    /// Authenticates user with biometrics
    /// - Returns: Publisher emitting authenticated user or error
    public func loginWithBiometrics() -> AnyPublisher<User, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthError.serviceUnavailable))
                return
            }
            
            guard self.authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
                promise(.failure(AuthError.biometricsNotAvailable))
                return
            }
            
            self.authContext.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: AuthConstants.BIOMETRIC_REASON
            ) { success, error in
                if success {
                    // Retrieve stored credentials and perform login
                    self.performBiometricLogin()
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    promise(.failure(error))
                                }
                            },
                            receiveValue: { user in
                                promise(.success(user))
                            }
                        )
                        .store(in: &self.cancellables)
                } else {
                    promise(.failure(error ?? AuthError.biometricsFailed))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Registers a new user
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - profile: User's initial profile data
    /// - Returns: Publisher emitting registered user or error
    public func register(email: String, password: String, profile: UserProfile) -> AnyPublisher<User, Error> {
        return validateDeviceIntegrity()
            .flatMap { isValid -> AnyPublisher<User, Error> in
                guard isValid else {
                    return Fail(error: AuthError.deviceIntegrityFailed).eraseToAnyPublisher()
                }
                
                let registrationData = [
                    "email": email,
                    "password": password,
                    "profile": profile
                ] as [String: Any]
                
                return APIClient.shared.request(endpoint: .auth(.signup), body: registrationData)
            }
            .eraseToAnyPublisher()
    }
    
    /// Logs out the current user
    public func logout() {
        // Clear tokens
        _ = KeychainManager.shared.removeToken(forKey: AuthConstants.AUTH_TOKEN_KEY)
        _ = KeychainManager.shared.removeToken(forKey: AuthConstants.REFRESH_TOKEN_KEY)
        
        // Reset state
        APIClient.shared.setAuthToken(nil)
        currentUser.send(nil)
        authState.send(.unauthenticated)
        
        // Clean up
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
        
        Logger.shared.info("User logged out successfully", category: "Auth")
    }
    
    // MARK: - Private Methods
    
    private func setupSecurityMonitoring() {
        // Monitor network status for security
        NetworkMonitor.shared.networkStatus
            .sink { [weak self] status in
                if case .disconnected = status {
                    self?.handleSecurityEvent(.networkDisconnected)
                }
            }
            .store(in: &cancellables)
        
        // Monitor auth state changes
        authState
            .sink { [weak self] state in
                self?.handleAuthStateChange(state)
            }
            .store(in: &cancellables)
    }
    
    private func restoreSession() {
        guard let token = try? KeychainManager.shared.retrieveToken(forKey: AuthConstants.AUTH_TOKEN_KEY).get() else {
            return
        }
        
        APIClient.shared.setAuthToken(token)
        setupTokenRefresh()
        
        // Fetch current user
        APIClient.shared.request(endpoint: .users(.profile))
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.logout()
                    }
                },
                receiveValue: { [weak self] (user: User) in
                    self?.currentUser.send(user)
                    self?.authState.send(.authenticated(user))
                }
            )
            .store(in: &cancellables)
    }
    
    private func validateDeviceIntegrity() -> AnyPublisher<Bool, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(AuthError.serviceUnavailable))
                return
            }
            
            // Check for jailbreak
            if self.isDeviceJailbroken() {
                Logger.shared.error("Device integrity check failed: Jailbreak detected", category: "Security")
                promise(.success(false))
                return
            }
            
            // Validate with DeviceCheck
            self.deviceCheck.generateToken { token, error in
                if let error = error {
                    Logger.shared.error("Device check failed: \(error.localizedDescription)", category: "Security")
                    promise(.success(false))
                } else {
                    promise(.success(true))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func setupTokenRefresh() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: AuthConstants.TOKEN_REFRESH_THRESHOLD, repeats: true) { [weak self] _ in
            self?.refreshTokenIfNeeded()
        }
    }
    
    private func refreshTokenIfNeeded() {
        guard let refreshToken = try? KeychainManager.shared.retrieveToken(forKey: AuthConstants.REFRESH_TOKEN_KEY).get() else {
            logout()
            return
        }
        
        APIClient.shared.request(endpoint: .auth(.refresh), body: ["refresh_token": refreshToken])
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.logout()
                    }
                },
                receiveValue: { [weak self] (response: AuthResponse) in
                    self?.handleTokenRefresh(response)
                }
            )
            .store(in: &cancellables)
    }
    
    private func handleLoginSuccess(_ response: AuthResponse, promise: (Result<User, Error>) -> Void) {
        // Save tokens
        _ = KeychainManager.shared.saveToken(response.accessToken, forKey: AuthConstants.AUTH_TOKEN_KEY)
        _ = KeychainManager.shared.saveToken(response.refreshToken, forKey: AuthConstants.REFRESH_TOKEN_KEY)
        
        // Configure client
        APIClient.shared.setAuthToken(response.accessToken)
        
        // Update state
        currentUser.send(response.user)
        authState.send(.authenticated(response.user))
        
        // Setup refresh timer
        setupTokenRefresh()
        
        // Reset login attempts
        loginAttempts = 0
        lastLoginAttempt = nil
        
        Logger.shared.info("User logged in successfully", category: "Auth")
        promise(.success(response.user))
    }
    
    private func handleLoginFailure(_ error: Error) {
        loginAttempts += 1
        lastLoginAttempt = Date()
        
        Logger.shared.error("Login failed: \(error.localizedDescription)", category: "Auth")
        
        if loginAttempts >= AuthConstants.MAX_LOGIN_ATTEMPTS {
            handleSecurityEvent(.exceededLoginAttempts)
        }
    }
    
    private func checkLoginRateLimit() -> Bool {
        if let lastAttempt = lastLoginAttempt,
           Date().timeIntervalSince(lastAttempt) < AuthConstants.LOGIN_COOLDOWN {
            return false
        }
        return loginAttempts < AuthConstants.MAX_LOGIN_ATTEMPTS
    }
    
    private func handleSecurityEvent(_ event: SecurityEvent) {
        switch event {
        case .exceededLoginAttempts:
            Logger.shared.error("Security event: Excessive login attempts detected", category: "Security")
            logout()
        case .networkDisconnected:
            Logger.shared.warning("Security event: Network disconnected", category: "Security")
        case .deviceIntegrityCompromised:
            Logger.shared.error("Security event: Device integrity compromised", category: "Security")
            logout()
        }
    }
    
    private func isDeviceJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // Check for common jailbreak paths
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
        #endif
    }
}

// MARK: - Supporting Types

private enum SecurityEvent {
    case exceededLoginAttempts
    case networkDisconnected
    case deviceIntegrityCompromised
}

private enum AuthError: LocalizedError {
    case serviceUnavailable
    case tooManyAttempts
    case deviceIntegrityFailed
    case biometricsNotAvailable
    case biometricsFailed
    
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Authentication service is currently unavailable"
        case .tooManyAttempts:
            return "Too many login attempts. Please try again later"
        case .deviceIntegrityFailed:
            return "Device security check failed"
        case .biometricsNotAvailable:
            return "Biometric authentication is not available"
        case .biometricsFailed:
            return "Biometric authentication failed"
        }
    }
}

private struct AuthResponse: Decodable {
    let user: User
    let accessToken: String
    let refreshToken: String
}