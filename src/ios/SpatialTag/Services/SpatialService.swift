//
// SpatialService.swift
// SpatialTag
//
// Core service managing spatial awareness, LiDAR processing, and location tracking
// with comprehensive error handling and performance optimization
//

import Combine // iOS 15.0+
import ARKit // 6.0
import CoreLocation // iOS 15.0+

// MARK: - Constants

private let SPATIAL_UPDATE_INTERVAL: TimeInterval = 1.0
private let MAX_NEARBY_USERS: Int = 50
private let LOCATION_ACCURACY_THRESHOLD: Double = 10.0
private let BATTERY_OPTIMIZATION_THRESHOLD: Double = 0.2
private let MAX_RETRY_ATTEMPTS: Int = 3

// MARK: - Error Types

enum SpatialError: Error {
    case lidarUnavailable
    case locationUnavailable
    case invalidRange
    case processingError
    case batteryLow
    case networkError
    case unauthorized
}

// MARK: - SpatialService

@available(iOS 15.0, *)
@MainActor
final class SpatialService {
    
    // MARK: - Properties
    
    private let lidarProcessor: LiDARProcessor
    private let locationManager: LocationManager
    private let apiClient: APIClient
    
    private let nearbyUsersPublisher = PassthroughSubject<[Location], Error>()
    private let userLocationPublisher = PassthroughSubject<Location, Error>()
    
    private var isTracking: Bool = false
    private let spatialLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(lidarProcessor: LiDARProcessor, locationManager: LocationManager) {
        self.lidarProcessor = lidarProcessor
        self.locationManager = locationManager
        self.apiClient = APIClient.shared
        
        setupBatteryMonitoring()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts spatial tracking with LiDAR and location updates
    /// - Returns: Publisher indicating tracking status with error handling
    func startSpatialTracking() -> AnyPublisher<Void, Error> {
        spatialLock.lock()
        defer { spatialLock.unlock() }
        
        guard !isTracking else {
            return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        
        // Check battery level for optimization
        guard UIDevice.current.batteryLevel > Float(BATTERY_OPTIMIZATION_THRESHOLD) else {
            return Fail(error: SpatialError.batteryLow).eraseToAnyPublisher()
        }
        
        let lidarPublisher = lidarProcessor.startScanning()
            .mapError { _ in SpatialError.lidarUnavailable }
        
        let locationPublisher = locationManager.startUpdatingLocation()
            .mapError { _ in SpatialError.locationUnavailable }
        
        isTracking = true
        
        return Publishers.CombineLatest(lidarPublisher, locationPublisher)
            .map { _, _ in () }
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.stopSpatialTracking()
                    }
                },
                receiveCancel: { [weak self] in
                    self?.stopSpatialTracking()
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Stops all spatial tracking and performs cleanup
    func stopSpatialTracking() {
        spatialLock.lock()
        defer { spatialLock.unlock() }
        
        guard isTracking else { return }
        
        lidarProcessor.stopScanning()
        locationManager.stopUpdatingLocation()
        cancellables.removeAll()
        isTracking = false
    }
    
    /// Discovers nearby users using LiDAR and location data
    /// - Parameter radius: Search radius in meters
    /// - Returns: Publisher streaming nearby user locations
    func findNearbyUsers(radius: Double) -> AnyPublisher<[Location], Error> {
        guard radius >= 0.5 && radius <= 50.0 else {
            return Fail(error: SpatialError.invalidRange).eraseToAnyPublisher()
        }
        
        return locationManager.findNearbyUsers(radius: radius, requiredAccuracy: LOCATION_ACCURACY_THRESHOLD)
            .flatMap { [weak self] locations -> AnyPublisher<[Location], Error> in
                guard let self = self else {
                    return Fail(error: SpatialError.processingError).eraseToAnyPublisher()
                }
                
                return self.enhanceLocationsWithLiDAR(locations)
                    .map { locations in
                        locations.prefix(MAX_NEARBY_USERS).map { $0 }
                    }
                    .eraseToAnyPublisher()
            }
            .handleEvents(receiveOutput: { [weak self] locations in
                self?.nearbyUsersPublisher.send(locations)
            })
            .eraseToAnyPublisher()
    }
    
    /// Updates user's location with enhanced spatial awareness
    /// - Parameter location: New location
    /// - Returns: Publisher with updated location
    func updateUserLocation(_ location: Location) -> AnyPublisher<Location, Error> {
        guard isTracking else {
            return Fail(error: SpatialError.processingError).eraseToAnyPublisher()
        }
        
        return lidarProcessor.updateSpatialMap()
            .flatMap { [weak self] spatialData -> AnyPublisher<Location, Error> in
                guard let self = self else {
                    return Fail(error: SpatialError.processingError).eraseToAnyPublisher()
                }
                
                var enhancedLocation = location
                try? enhancedLocation.updateSpatialCoordinate(spatialData.pointCloud.points[0])
                
                return self.syncLocationWithServer(enhancedLocation)
            }
            .handleEvents(receiveOutput: { [weak self] location in
                self?.userLocationPublisher.send(location)
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                if UIDevice.current.batteryLevel <= Float(BATTERY_OPTIMIZATION_THRESHOLD) {
                    self?.optimizePowerUsage()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: SPATIAL_UPDATE_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.monitorPerformance()
            }
            .store(in: &cancellables)
    }
    
    private func enhanceLocationsWithLiDAR(_ locations: [Location]) -> AnyPublisher<[Location], Error> {
        return lidarProcessor.updateSpatialMap()
            .map { spatialData in
                locations.map { location in
                    var enhanced = location
                    if let nearestPoint = self.findNearestSpatialPoint(to: location, in: spatialData) {
                        try? enhanced.updateSpatialCoordinate(nearestPoint)
                    }
                    return enhanced
                }
            }
            .eraseToAnyPublisher()
    }
    
    private func syncLocationWithServer(_ location: Location) -> AnyPublisher<Location, Error> {
        let endpoint = APIEndpoint.spatial(.update)
        return apiClient.request(endpoint: endpoint, body: location)
            .retry(MAX_RETRY_ATTEMPTS)
            .map { _ in location }
            .eraseToAnyPublisher()
    }
    
    private func findNearestSpatialPoint(to location: Location, in spatialData: SpatialData) -> simd_float3? {
        // Implementation would find the nearest LiDAR point to the given location
        return spatialData.pointCloud.points.first
    }
    
    private func optimizePowerUsage() {
        // Reduce update frequency and precision when battery is low
        lidarProcessor.stopScanning()
        locationManager.stopUpdatingLocation()
        
        // Restart with optimized settings
        _ = startSpatialTracking()
    }
    
    private func monitorPerformance() {
        // Monitor and log performance metrics
        Logger.performance("Spatial Processing",
                         duration: SPATIAL_UPDATE_INTERVAL,
                         threshold: 0.1,
                         metadata: [
                            "isTracking": isTracking,
                            "batteryLevel": UIDevice.current.batteryLevel
                         ])
    }
}