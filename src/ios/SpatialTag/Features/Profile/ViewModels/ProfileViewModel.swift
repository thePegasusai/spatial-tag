// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

// MARK: - Status Metrics Structure

private struct StatusMetrics {
    var totalPoints: Int
    var pointsToNextLevel: Int?
    var interactionCount: Int
    var spatialAccuracy: Double
    var lastUpdate: Date
}

// MARK: - Profile View Model

@MainActor
final class ProfileViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var profile: Profile
    @Published var isEditing: Bool = false
    @Published var displayName: String
    @Published var isVisible: Bool
    @Published var visibilityRadius: Int
    @Published var preferences: [String: Any]
    @Published var spatialData: Location?
    @Published var statusMetrics: StatusMetrics
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    var cancellables = Set<AnyCancellable>()
    private let userService: UserService
    private let performanceMonitor: PerformanceMonitor
    private let logger = Logger.shared
    private let updateThrottle: TimeInterval = 0.5
    private var lastUpdateTime: Date?
    
    // MARK: - Initialization
    
    init(profile: Profile, userService: UserService = .shared) {
        self.profile = profile
        self.userService = userService
        self.performanceMonitor = PerformanceMonitor()
        
        // Initialize published properties
        self.displayName = profile.displayName
        self.isVisible = profile.isVisible
        self.visibilityRadius = Int(profile.visibilityRadius)
        self.preferences = profile.preferences
        self.spatialData = profile.lastLocation
        
        // Initialize status metrics
        self.statusMetrics = StatusMetrics(
            totalPoints: profile.points,
            pointsToNextLevel: profile.statusLevel.pointsToNextLevel(currentPoints: profile.points),
            interactionCount: 0,
            spatialAccuracy: spatialData?.horizontalAccuracy ?? 0.0,
            lastUpdate: Date()
        )
        
        setupBindings()
        logger.debug("ProfileViewModel initialized for user: \(profile.id)")
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        refreshProfile()
        startPerformanceMonitoring()
    }
    
    func onDisappear() {
        cancellables.removeAll()
        performanceMonitor.stopTracking()
    }
    
    /// Updates the user profile with validation and security checks
    func updateProfile() -> AnyPublisher<Void, Error> {
        guard canPerformUpdate() else {
            return Fail(error: ProfileError.updateThrottled).eraseToAnyPublisher()
        }
        
        isLoading = true
        lastUpdateTime = Date()
        
        let startTime = Date()
        
        return userService.updateUserProfile(
            id: profile.id,
            displayName: displayName,
            isVisible: isVisible,
            visibilityRadius: Double(visibilityRadius),
            preferences: preferences
        )
        .handleEvents(
            receiveOutput: { [weak self] _ in
                guard let self = self else { return }
                
                let duration = Date().timeIntervalSince(startTime)
                self.logger.performance(
                    "Profile update",
                    duration: duration,
                    threshold: 1.0,
                    metadata: ["userId": self.profile.id.uuidString]
                )
                
                self.isLoading = false
            },
            receiveFailure: { [weak self] error in
                self?.handleError(error)
            }
        )
        .eraseToAnyPublisher()
    }
    
    /// Updates spatial preferences with LiDAR validation
    func updateSpatialPreferences(radius: Int, data: Location) -> AnyPublisher<Void, Error> {
        guard userService.validateLocationAccuracy(data) else {
            return Fail(error: ProfileError.insufficientPrecision).eraseToAnyPublisher()
        }
        
        isLoading = true
        
        return userService.updateSpatialData(
            userId: profile.id,
            location: data,
            radius: Double(radius)
        )
        .handleEvents(
            receiveOutput: { [weak self] _ in
                guard let self = self else { return }
                self.spatialData = data
                self.visibilityRadius = radius
                self.isLoading = false
                
                self.logger.debug("Spatial preferences updated for user: \(self.profile.id)")
            },
            receiveFailure: { [weak self] error in
                self?.handleError(error)
            }
        )
        .eraseToAnyPublisher()
    }
    
    /// Processes status updates based on engagement metrics
    func processStatusUpdate(metrics: StatusMetrics) -> AnyPublisher<StatusLevel, Error> {
        let points = calculateEngagementPoints(metrics)
        
        return userService.addUserPoints(
            userId: profile.id,
            points: points
        )
        .map { [weak self] newStatus in
            self?.statusMetrics = metrics
            return newStatus
        }
        .handleEvents(
            receiveOutput: { [weak self] newStatus in
                self?.logger.info("Status updated to \(newStatus) for user: \(self?.profile.id ?? UUID())")
            }
        )
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Monitor profile changes
        $displayName
            .dropFirst()
            .debounce(for: .seconds(updateThrottle), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.validateProfileChanges()
            }
            .store(in: &cancellables)
        
        // Monitor visibility changes
        $isVisible
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handleVisibilityChange(newValue)
            }
            .store(in: &cancellables)
    }
    
    private func refreshProfile() {
        userService.request(endpoint: .users(.profile))
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] (updatedProfile: Profile) in
                    self?.profile = updatedProfile
                    self?.updateLocalState(with: updatedProfile)
                }
            )
            .store(in: &cancellables)
    }
    
    private func updateLocalState(with profile: Profile) {
        displayName = profile.displayName
        isVisible = profile.isVisible
        visibilityRadius = Int(profile.visibilityRadius)
        preferences = profile.preferences
        spatialData = profile.lastLocation
    }
    
    private func validateProfileChanges() {
        guard displayName.count >= 3 else {
            error = ProfileError.invalidDisplayName
            return
        }
        
        executeTask {
            try await updateProfile().async()
        }
    }
    
    private func handleVisibilityChange(_ isVisible: Bool) {
        profile.updateVisibility(visible: isVisible, radius: Double(visibilityRadius))
    }
    
    private func canPerformUpdate() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) >= updateThrottle
    }
    
    private func calculateEngagementPoints(_ metrics: StatusMetrics) -> Int {
        let basePoints = metrics.interactionCount * 10
        let precisionBonus = metrics.spatialAccuracy <= 0.01 ? 50 : 0
        return basePoints + precisionBonus
    }
    
    private func startPerformanceMonitoring() {
        performanceMonitor.startTracking(
            category: "Profile",
            metadata: ["userId": profile.id.uuidString]
        )
    }
}

// MARK: - Error Types

private enum ProfileError: LocalizedError {
    case updateThrottled
    case insufficientPrecision
    case invalidDisplayName
    
    var errorDescription: String? {
        switch self {
        case .updateThrottled:
            return "Please wait before updating again"
        case .insufficientPrecision:
            return "Location precision does not meet requirements"
        case .invalidDisplayName:
            return "Display name must be at least 3 characters"
        }
    }
}

// MARK: - Performance Monitor

private final class PerformanceMonitor {
    private var startTime: Date?
    private let logger = Logger.shared
    
    func startTracking(category: String, metadata: [String: Any]) {
        startTime = Date()
        logger.debug("Started performance monitoring for \(category)")
    }
    
    func stopTracking() {
        guard let start = startTime else { return }
        let duration = Date().timeIntervalSince(start)
        logger.performance("Profile view session", duration: duration, threshold: 300.0)
    }
}