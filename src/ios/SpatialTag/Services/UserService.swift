// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine
// CoreLocation - iOS 15.0+ - Location services
import CoreLocation

/// Enhanced service managing user profile operations, location updates with LiDAR precision,
/// and secure status tracking in the Spatial Tag platform
@available(iOS 15.0, *)
public final class UserService {
    
    // MARK: - Constants
    
    private let LOCATION_UPDATE_INTERVAL: TimeInterval = 30.0
    private let NEARBY_USERS_RADIUS: Double = 50.0
    private let POINTS_PER_INTERACTION: Int = 10
    private let LIDAR_PRECISION_THRESHOLD: Double = 0.01
    private let MAX_LOCATION_AGE: TimeInterval = 300.0
    private let SECURITY_TOKEN_EXPIRY: TimeInterval = 3600.0
    
    // MARK: - Properties
    
    /// Shared singleton instance
    public static let shared = UserService()
    
    /// Publisher for nearby users updates
    public let nearbyUsers = CurrentValueSubject<[User], Never>([])
    
    /// Publisher for individual user updates
    public let userUpdates = PassthroughSubject<User, Never>()
    
    /// Publisher for performance metrics
    public let performanceMetrics = CurrentValueSubject<PerformanceMetrics, Never>(PerformanceMetrics())
    
    private let locationUpdateQueue = DispatchQueue(
        label: "com.spatialtag.userservice.location",
        qos: .userInitiated
    )
    
    private let securityValidator = SecurityValidator()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    private init() {
        setupUserUpdateSubscription()
        setupLocationUpdateTimer()
        setupPerformanceMonitoring()
        
        logger.debug("UserService initialized")
    }
    
    // MARK: - Public Methods
    
    /// Updates user's location with LiDAR precision and security validation
    /// - Parameter location: New location with LiDAR data
    /// - Returns: Publisher emitting nearby users or error
    public func updateUserLocation(_ location: Location) -> AnyPublisher<[User], Error> {
        let startTime = Date()
        
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(UserServiceError.serviceUnavailable))
                return
            }
            
            self.locationUpdateQueue.async {
                // Validate location precision
                guard self.validateLocationAccuracy(location) else {
                    self.logger.error("Location precision validation failed")
                    promise(.failure(UserServiceError.insufficientPrecision))
                    return
                }
                
                // Validate security token
                guard self.securityValidator.validateToken() else {
                    self.logger.error("Security token validation failed")
                    promise(.failure(UserServiceError.securityValidationFailed))
                    return
                }
                
                // Update current user's location
                guard let currentUser = AuthService.shared.currentUser.value else {
                    promise(.failure(UserServiceError.userNotAuthenticated))
                    return
                }
                
                // Update location in profile
                if case .failure(let error) = currentUser.profile.updateLocation(location) {
                    self.logger.error("Failed to update user location: \(error)")
                    promise(.failure(UserServiceError.locationUpdateFailed))
                    return
                }
                
                // Send location update to server
                let updateRequest = LocationUpdate(
                    userId: currentUser.id,
                    location: location,
                    timestamp: Date(),
                    precision: location.horizontalAccuracy
                )
                
                APIClient.shared.request(
                    endpoint: .spatial(.update),
                    body: updateRequest
                )
                .flatMap { (_: LocationUpdateResponse) -> AnyPublisher<[User], Error> in
                    // Fetch nearby users
                    return APIClient.shared.request(
                        endpoint: .spatial(.nearby),
                        body: ["radius": self.NEARBY_USERS_RADIUS]
                    )
                }
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { [weak self] (users: [User]) in
                        self?.handleNearbyUsersUpdate(users)
                        
                        // Update performance metrics
                        let duration = Date().timeIntervalSince(startTime)
                        self?.performanceMetrics.value.updateLocationMetrics(
                            duration: duration,
                            usersCount: users.count
                        )
                        
                        promise(.success(users))
                    }
                )
                .store(in: &self.cancellables)
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Validates location data precision using LiDAR measurements
    /// - Parameter location: Location to validate
    /// - Returns: Boolean indicating if location meets precision requirements
    public func validateLocationAccuracy(_ location: Location) -> Bool {
        guard let spatialCoordinate = location.spatialCoordinate else {
            logger.warning("No LiDAR data available for location validation")
            return false
        }
        
        let precision = Double(simd_length(spatialCoordinate))
        let isValid = precision <= LIDAR_PRECISION_THRESHOLD
        
        logger.debug("Location precision validation: \(precision) (threshold: \(LIDAR_PRECISION_THRESHOLD))")
        return isValid
    }
    
    // MARK: - Private Methods
    
    private func setupUserUpdateSubscription() {
        AuthService.shared.currentUser
            .compactMap { $0 }
            .sink { [weak self] user in
                self?.handleUserUpdate(user)
            }
            .store(in: &cancellables)
    }
    
    private func setupLocationUpdateTimer() {
        Timer.publish(every: LOCATION_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkLocationAge()
            }
            .store(in: &cancellables)
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.monitorPerformance()
            }
            .store(in: &cancellables)
    }
    
    private func handleNearbyUsersUpdate(_ users: [User]) {
        nearbyUsers.send(users)
        
        // Filter out current user
        let filteredUsers = users.filter { user in
            user.id != AuthService.shared.currentUser.value?.id
        }
        
        // Update user statuses based on proximity
        filteredUsers.forEach { user in
            if let currentUser = AuthService.shared.currentUser.value {
                let points = calculateInteractionPoints(for: user)
                _ = currentUser.updateStatus(pointsEarned: points)
            }
        }
    }
    
    private func handleUserUpdate(_ user: User) {
        userUpdates.send(user)
    }
    
    private func calculateInteractionPoints(for user: User) -> Int {
        guard let currentUser = AuthService.shared.currentUser.value,
              let userLocation = user.profile.lastLocation,
              let currentLocation = currentUser.profile.lastLocation else {
            return 0
        }
        
        // Calculate points based on proximity and status
        let distance = currentLocation.distanceTo(userLocation)
        if case .success(let meters) = distance {
            return Int(Double(POINTS_PER_INTERACTION) * (1.0 - meters / NEARBY_USERS_RADIUS))
        }
        
        return 0
    }
    
    private func checkLocationAge() {
        guard let currentUser = AuthService.shared.currentUser.value,
              let lastLocation = currentUser.profile.lastLocation else {
            return
        }
        
        let age = Date().timeIntervalSince(lastLocation.timestamp)
        if age > MAX_LOCATION_AGE {
            logger.warning("Location data age exceeds threshold: \(age) seconds")
        }
    }
    
    private func monitorPerformance() {
        let metrics = performanceMetrics.value
        
        if metrics.averageUpdateDuration > 1.0 {
            logger.performance(
                "Location update performance degraded",
                duration: metrics.averageUpdateDuration,
                threshold: 1.0,
                metadata: [
                    "userCount": metrics.lastUserCount,
                    "precision": metrics.averagePrecision
                ]
            )
        }
    }
}

// MARK: - Supporting Types

private struct LocationUpdate: Encodable {
    let userId: UUID
    let location: Location
    let timestamp: Date
    let precision: Double
}

private struct LocationUpdateResponse: Decodable {
    let success: Bool
    let timestamp: Date
}

private struct PerformanceMetrics {
    var averageUpdateDuration: TimeInterval = 0
    var lastUserCount: Int = 0
    var averagePrecision: Double = 0
    var updateCount: Int = 0
    
    mutating func updateLocationMetrics(duration: TimeInterval, usersCount: Int) {
        updateCount += 1
        averageUpdateDuration = (averageUpdateDuration * Double(updateCount - 1) + duration) / Double(updateCount)
        lastUserCount = usersCount
    }
}

private class SecurityValidator {
    func validateToken() -> Bool {
        // Implement token validation logic
        return true
    }
}

private enum UserServiceError: LocalizedError {
    case serviceUnavailable
    case insufficientPrecision
    case securityValidationFailed
    case userNotAuthenticated
    case locationUpdateFailed
    
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "User service is currently unavailable"
        case .insufficientPrecision:
            return "Location precision does not meet requirements"
        case .securityValidationFailed:
            return "Security validation failed"
        case .userNotAuthenticated:
            return "User is not authenticated"
        case .locationUpdateFailed:
            return "Failed to update user location"
        }
    }
}