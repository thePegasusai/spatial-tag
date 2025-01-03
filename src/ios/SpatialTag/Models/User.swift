//
// User.swift
// SpatialTag
//
// Core model representing a user in the Spatial Tag application with
// secure authentication, LiDAR-enabled location tracking, and status management
//

import Foundation
import LocalAuthentication

// MARK: - Constants

private let SESSION_TIMEOUT: TimeInterval = 3600.0
private let MAX_FAILED_ATTEMPTS: Int = 3
private let LOCATION_UPDATE_INTERVAL: TimeInterval = 30.0
private let MIN_LIDAR_PRECISION: Double = 0.01

// MARK: - Error Types

enum AuthError: Error {
    case invalidCredentials
    case accountLocked
    case biometricsNotAvailable
    case sessionExpired
    case biometricsFailed
}

enum LocationError: Error {
    case invalidLocation
    case precisionNotMet
    case updateFailed
}

// MARK: - User Class

@objc
@objcMembers
public class User: NSObject {
    
    // MARK: - Properties
    
    public let id: UUID
    public let email: String
    public private(set) var profile: Profile
    public private(set) var isAuthenticated: Bool
    public private(set) var lastLoginDate: Date?
    private var failedLoginAttempts: Int
    private var biometricsEnabled: Bool
    private var sessionToken: String?
    private var sessionExpiry: Date?
    
    private let locationLock = NSLock()
    private let authLock = NSLock()
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    public init(id: UUID, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.profile = Profile(id: id, displayName: displayName)
        self.isAuthenticated = false
        self.lastLoginDate = nil
        self.failedLoginAttempts = 0
        self.biometricsEnabled = false
        self.sessionToken = nil
        self.sessionExpiry = nil
        
        super.init()
        
        logger.debug("User initialized: \(id.uuidString)")
    }
    
    // MARK: - Authentication
    
    public func authenticate(credentials: String, useBiometrics: Bool) -> Result<Bool, AuthError> {
        authLock.lock()
        defer { authLock.unlock() }
        
        // Check for account lockout
        if failedLoginAttempts >= MAX_FAILED_ATTEMPTS {
            logger.warning("Account locked for user: \(id.uuidString)")
            return .failure(.accountLocked)
        }
        
        // Handle biometric authentication
        if useBiometrics {
            let context = LAContext()
            var error: NSError?
            
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                logger.error("Biometrics not available: \(error?.localizedDescription ?? "Unknown error")")
                return .failure(.biometricsNotAvailable)
            }
            
            var authResult = false
            let semaphore = DispatchSemaphore(value: 0)
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                 localizedReason: "Authenticate to access Spatial Tag") { success, error in
                authResult = success
                semaphore.signal()
            }
            
            _ = semaphore.wait(timeout: .now() + 30.0)
            
            if !authResult {
                logger.error("Biometric authentication failed for user: \(id.uuidString)")
                return .failure(.biometricsFailed)
            }
        } else {
            // Validate credentials (implementation would depend on your auth system)
            guard validateCredentials(credentials) else {
                failedLoginAttempts += 1
                logger.warning("Failed login attempt (\(failedLoginAttempts)) for user: \(id.uuidString)")
                return .failure(.invalidCredentials)
            }
        }
        
        // Update authentication state
        isAuthenticated = true
        failedLoginAttempts = 0
        lastLoginDate = Date()
        sessionToken = UUID().uuidString
        sessionExpiry = Date().addingTimeInterval(SESSION_TIMEOUT)
        biometricsEnabled = useBiometrics
        
        logger.info("User authenticated successfully: \(id.uuidString)")
        return .success(true)
    }
    
    // MARK: - Location Management
    
    public func updateLocation(_ newLocation: Location) -> Result<Void, LocationError> {
        locationLock.lock()
        defer { locationLock.unlock() }
        
        // Validate session
        guard isSessionValid() else {
            logger.warning("Session expired during location update for user: \(id.uuidString)")
            return .failure(.updateFailed)
        }
        
        // Validate location precision
        if let spatialCoordinate = newLocation.spatialCoordinate {
            let precision = Double(simd_length(spatialCoordinate))
            guard precision >= MIN_LIDAR_PRECISION else {
                logger.warning("Location precision below threshold: \(precision)")
                return .failure(.precisionNotMet)
            }
        }
        
        // Update profile location
        guard profile.updateLocation(newLocation) else {
            logger.error("Failed to update location for user: \(id.uuidString)")
            return .failure(.updateFailed)
        }
        
        logger.debug("Location updated for user: \(id.uuidString)")
        return .success(())
    }
    
    // MARK: - Status Management
    
    public func updateStatus(pointsEarned: Int) -> StatusLevel {
        guard isSessionValid() else {
            logger.warning("Session expired during status update for user: \(id.uuidString)")
            return profile.statusLevel
        }
        
        let newStatus = profile.addPoints(pointsEarned)
        
        if newStatus != profile.statusLevel {
            logger.info("Status level changed for user \(id.uuidString): \(profile.statusLevel) -> \(newStatus)")
        }
        
        return newStatus
    }
    
    // MARK: - Private Helpers
    
    private func isSessionValid() -> Bool {
        guard let expiry = sessionExpiry else { return false }
        return isAuthenticated && Date() < expiry
    }
    
    private func validateCredentials(_ credentials: String) -> Bool {
        // Implementation would depend on your authentication system
        // This is a placeholder for the actual validation logic
        return !credentials.isEmpty
    }
}

// MARK: - Codable Conformance

extension User: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, email, profile, isAuthenticated, lastLoginDate
        case failedLoginAttempts, biometricsEnabled
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(email, forKey: .email)
        try container.encode(profile, forKey: .profile)
        try container.encode(isAuthenticated, forKey: .isAuthenticated)
        try container.encode(lastLoginDate, forKey: .lastLoginDate)
        try container.encode(failedLoginAttempts, forKey: .failedLoginAttempts)
        try container.encode(biometricsEnabled, forKey: .biometricsEnabled)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        profile = try container.decode(Profile.self, forKey: .profile)
        isAuthenticated = try container.decode(Bool.self, forKey: .isAuthenticated)
        lastLoginDate = try container.decodeIfPresent(Date.self, forKey: .lastLoginDate)
        failedLoginAttempts = try container.decode(Int.self, forKey: .failedLoginAttempts)
        biometricsEnabled = try container.decode(Bool.self, forKey: .biometricsEnabled)
        
        super.init()
    }
}