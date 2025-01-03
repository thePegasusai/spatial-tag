// Foundation - Core iOS functionality (iOS 15.0+)
import Foundation
// Security - Keychain Services API (iOS 15.0+)
import Security
// LocalAuthentication - Biometric authentication (iOS 15.0+)
import LocalAuthentication

/// Comprehensive error enumeration for keychain operations
@objc public enum KeychainError: Int, Error {
    case unhandledError = -1
    case itemNotFound = -25300
    case duplicateItem = -25299
    case authFailed = -25293
    case biometricNotAvailable = -25291
    case invalidInput = -25292
    case tokenExpired = -25294
    case secureEnclaveNotAvailable = -25295
    
    var localizedDescription: String {
        switch self {
        case .unhandledError: return "An unhandled keychain error occurred"
        case .itemNotFound: return "The specified item was not found in keychain"
        case .duplicateItem: return "The item already exists in keychain"
        case .authFailed: return "Authentication failed"
        case .biometricNotAvailable: return "Biometric authentication is not available"
        case .invalidInput: return "Invalid input parameters"
        case .tokenExpired: return "The stored token has expired"
        case .secureEnclaveNotAvailable: return "Secure Enclave is not available"
        }
    }
}

/// Access control levels for keychain items
@objc public enum KeychainAccessibility: Int {
    case afterFirstUnlock
    case afterFirstUnlockThisDeviceOnly
    case whenUnlocked
    case whenUnlockedThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly
    
    var secAccessibility: CFString {
        switch self {
        case .afterFirstUnlock: return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked: return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly: return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

/// Enhanced keychain manager with secure enclave and biometric support
@objc public class KeychainManager: NSObject {
    // MARK: - Constants
    private let SERVICE_IDENTIFIER = "com.spatialtag.keychain"
    private let ACCESS_GROUP = "com.spatialtag.shared"
    private let TOKEN_EXPIRATION_INTERVAL: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    // MARK: - Properties
    private let operationQueue: DispatchQueue
    private let authContext: LAContext
    private var isSecureEnclaveAvailable: Bool
    
    // MARK: - Singleton
    @objc public static let shared = KeychainManager()
    
    private override init() {
        self.operationQueue = DispatchQueue(label: "com.spatialtag.keychain.queue", qos: .userInitiated)
        self.authContext = LAContext()
        
        // Check Secure Enclave availability
        var error: NSError?
        self.isSecureEnclaveAvailable = authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        super.init()
        Logger.shared.debug("KeychainManager initialized with Secure Enclave status: \(isSecureEnclaveAvailable)")
    }
    
    // MARK: - Public Methods
    
    /// Saves a token securely in the keychain with optional biometric protection
    @objc public func saveToken(_ token: String, 
                               forKey key: String,
                               accessibility: KeychainAccessibility = .whenUnlockedThisDeviceOnly,
                               requiresBiometric: Bool = false) -> Result<Bool, KeychainError> {
        let startTime = Date()
        
        guard !token.isEmpty && !key.isEmpty else {
            Logger.shared.error("Invalid input parameters for token storage")
            return .failure(.invalidInput)
        }
        
        return operationQueue.sync { [weak self] in
            guard let self = self else { return .failure(.unhandledError) }
            
            // Configure access control
            var accessControl: SecAccessControl?
            var error: Unmanaged<CFError>?
            
            if requiresBiometric && isSecureEnclaveAvailable {
                accessControl = SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    accessibility.secAccessibility,
                    .biometryAny,
                    &error
                )
            } else {
                accessControl = SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    accessibility.secAccessibility,
                    [],
                    &error
                )
            }
            
            guard error == nil, let accessControl = accessControl else {
                Logger.shared.error("Failed to create access control")
                return .failure(.unhandledError)
            }
            
            // Prepare token data with expiration
            let tokenData = token.data(using: .utf8)!
            let expirationDate = Date().addingTimeInterval(TOKEN_EXPIRATION_INTERVAL)
            let tokenContainer: [String: Any] = [
                "token": tokenData,
                "expiration": expirationDate
            ]
            
            let containerData = try? JSONSerialization.data(withJSONObject: tokenContainer)
            
            // Configure keychain query
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: SERVICE_IDENTIFIER,
                kSecAttrAccount as String: key,
                kSecAttrAccessGroup as String: ACCESS_GROUP,
                kSecAttrAccessControl as String: accessControl,
                kSecValueData as String: containerData as Any
            ]
            
            // Attempt to save token
            let status = SecItemAdd(query as CFDictionary, nil)
            
            if status == errSecDuplicateItem {
                // Update existing item
                let updateQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: SERVICE_IDENTIFIER,
                    kSecAttrAccount as String: key
                ]
                
                let updateAttributes: [String: Any] = [
                    kSecValueData as String: containerData as Any,
                    kSecAttrAccessControl as String: accessControl
                ]
                
                let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
                
                if updateStatus != errSecSuccess {
                    Logger.shared.error("Failed to update existing token: \(updateStatus)")
                    return .failure(.unhandledError)
                }
            } else if status != errSecSuccess {
                Logger.shared.error("Failed to save token: \(status)")
                return .failure(.unhandledError)
            }
            
            Logger.shared.performance("Token save operation",
                                   duration: Date().timeIntervalSince(startTime),
                                   threshold: 1.0)
            return .success(true)
        }
    }
    
    /// Retrieves a token from the keychain with optional biometric verification
    @objc public func retrieveToken(forKey key: String,
                                  requiresBiometric: Bool = false) -> Result<String?, KeychainError> {
        let startTime = Date()
        
        guard !key.isEmpty else {
            Logger.shared.error("Invalid key for token retrieval")
            return .failure(.invalidInput)
        }
        
        return operationQueue.sync { [weak self] in
            guard let self = self else { return .failure(.unhandledError) }
            
            if requiresBiometric && isSecureEnclaveAvailable {
                var error: NSError?
                guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                    Logger.shared.error("Biometric authentication not available: \(error?.localizedDescription ?? "Unknown error")")
                    return .failure(.biometricNotAvailable)
                }
                
                var authError: NSError?
                let authResult = authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                          localizedReason: "Authenticate to access secure data",
                                                          error: &authError)
                
                guard authResult else {
                    Logger.shared.error("Biometric authentication failed: \(authError?.localizedDescription ?? "Unknown error")")
                    return .failure(.authFailed)
                }
            }
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: SERVICE_IDENTIFIER,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            guard status == errSecSuccess,
                  let containerData = result as? Data,
                  let containerDict = try? JSONSerialization.jsonObject(with: containerData) as? [String: Any],
                  let tokenData = containerDict["token"] as? Data,
                  let expirationDate = containerDict["expiration"] as? Date,
                  let token = String(data: tokenData, encoding: .utf8) else {
                Logger.shared.error("Failed to retrieve token: \(status)")
                return .failure(KeychainError(rawValue: Int(status)) ?? .unhandledError)
            }
            
            // Check token expiration
            if Date() > expirationDate {
                Logger.shared.debug("Token expired")
                return .failure(.tokenExpired)
            }
            
            Logger.shared.performance("Token retrieval operation",
                                   duration: Date().timeIntervalSince(startTime),
                                   threshold: 0.5)
            return .success(token)
        }
    }
    
    /// Rotates an existing token with a new one
    @objc public func rotateToken(forKey key: String,
                                newToken: String) -> Result<Bool, KeychainError> {
        let startTime = Date()
        
        return operationQueue.sync { [weak self] in
            guard let self = self else { return .failure(.unhandledError) }
            
            // First verify the existing token
            let retrieveResult = retrieveToken(forKey: key)
            guard case .success = retrieveResult else {
                Logger.shared.error("Cannot rotate non-existent token")
                return .failure(.itemNotFound)
            }
            
            // Save new token with same settings
            let saveResult = saveToken(newToken,
                                     forKey: key,
                                     accessibility: .whenUnlockedThisDeviceOnly)
            
            Logger.shared.performance("Token rotation operation",
                                   duration: Date().timeIntervalSince(startTime),
                                   threshold: 1.5)
            return saveResult
        }
    }
    
    /// Removes a token from the keychain
    @objc public func removeToken(forKey key: String) -> Result<Bool, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SERVICE_IDENTIFIER,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.shared.error("Failed to remove token: \(status)")
            return .failure(KeychainError(rawValue: Int(status)) ?? .unhandledError)
        }
        
        return .success(true)
    }
}