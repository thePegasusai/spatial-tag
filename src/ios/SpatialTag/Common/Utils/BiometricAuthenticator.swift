// Foundation - Core iOS functionality (iOS 15.0+)
import Foundation
// LocalAuthentication - Biometric authentication APIs (iOS 15.0+)
import LocalAuthentication

// MARK: - Constants
private let BIOMETRIC_STATE_KEY = "com.spatialtag.security.biometric_authentication_enabled"
private let MAX_AUTH_ATTEMPTS = 3
private let AUTH_TIMEOUT = 30.0

// MARK: - BiometricError Enumeration
@objc public enum BiometricError: Int, Error {
    case notAvailable = -1
    case notEnrolled = -2
    case lockout = -3
    case maxAttemptsExceeded = -4
    case cancelled = -5
    case timeout = -6
    case unknown = -99
    
    var localizedDescription: String {
        switch self {
        case .notAvailable: return "Biometric authentication is not available"
        case .notEnrolled: return "No biometric data is enrolled"
        case .lockout: return "Biometric authentication is locked out"
        case .maxAttemptsExceeded: return "Maximum authentication attempts exceeded"
        case .cancelled: return "Authentication was cancelled"
        case .timeout: return "Authentication timed out"
        case .unknown: return "An unknown error occurred"
        }
    }
}

// MARK: - BiometricAuthenticator Class
@objc public class BiometricAuthenticator: NSObject {
    // MARK: - Properties
    private let context: LAContext
    private var isBiometricsAvailable: Bool
    private var biometryType: LABiometryType
    private var authenticationAttempts: Int
    private let securityQueue: DispatchQueue
    private let authLock: NSLock
    
    // MARK: - Singleton
    @objc public static let shared = BiometricAuthenticator()
    
    // MARK: - Initialization
    private override init() {
        self.context = LAContext()
        self.isBiometricsAvailable = false
        self.biometryType = .none
        self.authenticationAttempts = 0
        self.securityQueue = DispatchQueue(label: "com.spatialtag.biometric.queue", qos: .userInitiated)
        self.authLock = NSLock()
        
        super.init()
        
        // Initialize biometric state
        var error: NSError?
        self.isBiometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        self.biometryType = context.biometryType
        
        Logger.shared.debug("BiometricAuthenticator initialized - Available: \(isBiometricsAvailable), Type: \(biometryType.rawValue)")
    }
    
    // MARK: - Public Methods
    
    /// Checks if biometric authentication can be used
    @objc public func canUseBiometrics() -> Bool {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        if let error = error {
            Logger.shared.error("Biometric availability check failed: \(error.localizedDescription)")
            return false
        }
        
        return canEvaluate && isBiometricsAvailable
    }
    
    /// Authenticates user with biometrics
    @objc public func authenticateUser(reason: String, completion: @escaping (Result<Bool, BiometricError>) -> Void) {
        authLock.lock()
        defer { authLock.unlock() }
        
        // Check authentication attempts
        if authenticationAttempts >= MAX_AUTH_ATTEMPTS {
            Logger.shared.security("Maximum authentication attempts exceeded")
            completion(.failure(.maxAttemptsExceeded))
            return
        }
        
        // Verify biometric availability
        guard canUseBiometrics() else {
            Logger.shared.error("Biometric authentication not available")
            completion(.failure(.notAvailable))
            return
        }
        
        // Configure authentication context
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedFallbackTitle = "Use Passcode"
        context.localizedCancelTitle = "Cancel"
        
        let startTime = Date()
        
        // Perform authentication
        securityQueue.async { [weak self] in
            guard let self = self else { return }
            
            let semaphore = DispatchSemaphore(value: 0)
            var authResult: Result<Bool, BiometricError> = .failure(.unknown)
            
            // Start authentication with timeout
            DispatchQueue.global().async {
                self.context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                ) { success, error in
                    if success {
                        Logger.shared.security("Biometric authentication successful")
                        self.authenticationAttempts = 0
                        authResult = .success(true)
                    } else if let error = error as? LAError {
                        self.authenticationAttempts += 1
                        Logger.shared.error("Biometric authentication failed: \(error.localizedDescription)")
                        
                        switch error.code {
                        case .biometryNotAvailable:
                            authResult = .failure(.notAvailable)
                        case .biometryNotEnrolled:
                            authResult = .failure(.notEnrolled)
                        case .biometryLockout:
                            authResult = .failure(.lockout)
                        case .userCancel:
                            authResult = .failure(.cancelled)
                        default:
                            authResult = .failure(.unknown)
                        }
                    }
                    semaphore.signal()
                }
            }
            
            // Handle timeout
            if semaphore.wait(timeout: .now() + AUTH_TIMEOUT) == .timedOut {
                Logger.shared.error("Biometric authentication timed out")
                authResult = .failure(.timeout)
            }
            
            // Log performance metrics
            Logger.shared.performance(
                "Biometric authentication",
                duration: Date().timeIntervalSince(startTime),
                threshold: 2.0,
                metadata: ["attempts": self.authenticationAttempts]
            )
            
            DispatchQueue.main.async {
                completion(authResult)
            }
        }
    }
    
    /// Sets biometric authentication enabled state
    @objc public func setBiometricAuthenticationEnabled(_ enabled: Bool) -> Bool {
        let result = KeychainManager.shared.saveToken(
            String(enabled),
            forKey: BIOMETRIC_STATE_KEY,
            accessibility: .whenUnlockedThisDeviceOnly
        )
        
        switch result {
        case .success:
            Logger.shared.debug("Biometric authentication state updated: \(enabled)")
            return true
        case .failure(let error):
            Logger.shared.error("Failed to save biometric state: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Checks if biometric authentication is enabled
    @objc public func isBiometricAuthenticationEnabled() -> Bool {
        let result = KeychainManager.shared.retrieveToken(forKey: BIOMETRIC_STATE_KEY)
        
        switch result {
        case .success(let value):
            return value == "true"
        case .failure:
            Logger.shared.debug("No biometric state found, defaulting to false")
            return false
        }
    }
}