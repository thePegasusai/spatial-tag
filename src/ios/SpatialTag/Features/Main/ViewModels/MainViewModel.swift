// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming
import Combine
// os.log - iOS 15.0+ - System logging
import os.log

/// Core view model managing the main screen's state and business logic
@available(iOS 15.0, *)
@MainActor
final class MainViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var nearbyUsers: [User] = []
    @Published private(set) var nearbyTags: [Tag] = []
    @Published private(set) var isSpatialTrackingActive: Bool = false
    @Published private(set) var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published private(set) var batteryStatus: BatteryStatus = BatteryStatus()
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private let spatialService: SpatialService
    private let tagService: TagService
    private var refreshTimer: Timer?
    private var locationUpdateTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()
    
    private let logger = Logger.shared
    private let refreshInterval: TimeInterval = 1.0
    private let nearbyRadius: Double = 50.0
    private let batteryThreshold: Double = 0.15
    private let performanceThreshold: TimeInterval = 30.0
    
    // MARK: - Initialization
    
    init(spatialService: SpatialService, tagService: TagService) {
        self.spatialService = spatialService
        self.tagService = tagService
        
        setupBatteryMonitoring()
        setupPerformanceMonitoring()
        setupStateRecovery()
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        startTracking()
    }
    
    func onDisappear() {
        stopTracking()
    }
    
    /// Starts spatial tracking and nearby discovery with performance optimization
    func startTracking() {
        guard !isSpatialTrackingActive else { return }
        
        isLoading = true
        
        // Start spatial tracking with battery optimization
        spatialService.startSpatialTracking()
            .flatMap { [weak self] _ -> AnyPublisher<Void, Error> in
                guard let self = self else { return Empty().eraseToAnyPublisher() }
                return self.startNearbyDiscovery()
            }
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                    self?.isLoading = false
                },
                receiveValue: { [weak self] _ in
                    self?.isSpatialTrackingActive = true
                    self?.configureRefreshTimer()
                    self?.isLoading = false
                }
            )
            .store(in: &cancellables)
    }
    
    /// Stops all spatial tracking with resource cleanup
    func stopTracking() {
        guard isSpatialTrackingActive else { return }
        
        spatialService.stopSpatialTracking()
        refreshTimer?.invalidate()
        refreshTimer = nil
        locationUpdateTask?.cancel()
        
        nearbyUsers.removeAll()
        nearbyTags.removeAll()
        isSpatialTrackingActive = false
        
        persistCurrentState()
    }
    
    // MARK: - Private Methods
    
    private func startNearbyDiscovery() -> AnyPublisher<Void, Error> {
        let usersPublisher = spatialService.findNearbyUsers(radius: nearbyRadius)
            .catch { error -> AnyPublisher<[Location], Error> in
                self.logger.error("Failed to find nearby users: \(error.localizedDescription)")
                return Empty().eraseToAnyPublisher()
            }
        
        let tagsPublisher = tagService.getNearbyTags(radius: nearbyRadius)
            .catch { error -> AnyPublisher<[Tag], Error> in
                self.logger.error("Failed to get nearby tags: \(error.localizedDescription)")
                return Empty().eraseToAnyPublisher()
            }
        
        return Publishers.CombineLatest(usersPublisher, tagsPublisher)
            .map { [weak self] users, tags in
                self?.updateNearbyEntities(users: users, tags: tags)
            }
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    private func configureRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.batteryStatus.level > self.batteryThreshold {
                self.refreshNearbyEntities()
            } else {
                self.optimizeForLowBattery()
            }
        }
    }
    
    private func refreshNearbyEntities() {
        locationUpdateTask?.cancel()
        locationUpdateTask = Task { [weak self] in
            guard let self = self else { return }
            
            let startTime = DispatchTime.now()
            
            do {
                let users = try await self.spatialService.findNearbyUsers(radius: self.nearbyRadius).async()
                let tags = try await self.tagService.getNearbyTags(radius: self.nearbyRadius).async()
                
                await self.updateNearbyEntities(users: users, tags: tags)
                
                let endTime = DispatchTime.now()
                let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
                
                self.updatePerformanceMetrics(duration: duration)
            } catch {
                self.logger.error("Failed to refresh nearby entities: \(error.localizedDescription)")
            }
        }
    }
    
    private func updateNearbyEntities(users: [Location], tags: [Tag]) {
        // Filter and sort users by distance
        self.nearbyUsers = users
            .compactMap { location in
                // Convert location to user (implementation would depend on your data model)
                return User(id: UUID(), email: "", displayName: "")
            }
            .sorted { $0.profile.lastLocation?.distanceTo(users[0]) ?? .success(Double.infinity) < $1.profile.lastLocation?.distanceTo(users[0]) ?? .success(Double.infinity) }
        
        // Filter expired tags and sort by distance
        self.nearbyTags = tags
            .filter { !$0.isExpired() }
            .sorted { $0.location.distanceTo(users[0]) ?? .success(Double.infinity) < $1.location.distanceTo(users[0]) ?? .success(Double.infinity) }
    }
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateBatteryStatus()
            }
            .store(in: &cancellables)
        
        updateBatteryStatus()
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPerformance()
            }
            .store(in: &cancellables)
    }
    
    private func setupStateRecovery() {
        // Implement state recovery from persistent storage if needed
    }
    
    private func updateBatteryStatus() {
        batteryStatus = BatteryStatus(
            level: Double(UIDevice.current.batteryLevel),
            state: UIDevice.current.batteryState
        )
        
        if batteryStatus.level <= batteryThreshold {
            optimizeForLowBattery()
        }
    }
    
    private func optimizeForLowBattery() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval * 3, repeats: true) { [weak self] _ in
            self?.refreshNearbyEntities()
        }
    }
    
    private func checkPerformance() {
        let metrics = performanceMetrics
        
        if metrics.refreshDuration > performanceThreshold {
            logger.warning("Performance threshold exceeded: \(metrics.refreshDuration)s")
            optimizePerformance()
        }
    }
    
    private func updatePerformanceMetrics(duration: TimeInterval) {
        performanceMetrics = PerformanceMetrics(
            refreshDuration: duration,
            timestamp: Date(),
            batteryImpact: batteryStatus.level - UIDevice.current.batteryLevel
        )
    }
    
    private func optimizePerformance() {
        // Implement performance optimization strategies
    }
    
    private func persistCurrentState() {
        // Implement state persistence if needed
    }
}

// MARK: - Supporting Types

struct PerformanceMetrics {
    var refreshDuration: TimeInterval = 0
    var timestamp: Date = Date()
    var batteryImpact: Double = 0
}

struct BatteryStatus {
    var level: Double = 1.0
    var state: UIDevice.BatteryState = .unknown
}