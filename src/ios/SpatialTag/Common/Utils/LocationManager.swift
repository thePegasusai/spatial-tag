//
// LocationManager.swift
// SpatialTag
//
// Core location management utility with LiDAR integration and performance optimization
//
// CoreLocation Version: iOS 15.0+
// Combine Version: iOS 15.0+
//

import CoreLocation
import Combine
import os.log

// MARK: - Constants

private enum LocationConstants {
    static let LOCATION_UPDATE_INTERVAL: TimeInterval = 1.0
    static let DESIRED_ACCURACY: CLLocationAccuracy = kCLLocationAccuracyBest
    static let MIN_DETECTION_RANGE: Double = 0.5
    static let MAX_DETECTION_RANGE: Double = 50.0
    static let BATTERY_THRESHOLD: Double = 0.2
    static let ACCURACY_THRESHOLD: Double = 5.0
    static let LOCATION_CACHE_DURATION: TimeInterval = 30.0
}

// MARK: - Error Types

enum LocationError: Error {
    case unauthorized
    case locationServicesDisabled
    case invalidAccuracy
    case outOfRange
    case lidarUnavailable
    case batteryLow
    case precisionValidationFailed
}

// MARK: - LocationManager Class

@objc
@objcMembers
final class LocationManager: NSObject {
    
    // MARK: - Properties
    
    private let locationManager: CLLocationManager
    private let locationPublisher = PassthroughSubject<Location, LocationError>()
    private let nearbyUsersPublisher = PassthroughSubject<[Location], LocationError>()
    private let locationLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private let performanceLog = OSLog(subsystem: "com.spatialtag.location", category: "Performance")
    
    private(set) var isUpdating: Bool = false
    private(set) var currentLocation: Location?
    
    // MARK: - Initialization
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        
        configureLocationManager()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Requests location permission with enhanced error handling
    /// - Returns: Publisher streaming authorization status
    func requestLocationPermission() -> AnyPublisher<CLAuthorizationStatus, LocationError> {
        return Future { [weak self] promise in
            guard CLLocationManager.locationServicesEnabled() else {
                promise(.failure(.locationServicesDisabled))
                return
            }
            
            self?.locationManager.requestWhenInUseAuthorization()
            
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                .map { _ in CLLocationManager.authorizationStatus() }
                .map { status -> Result<CLAuthorizationStatus, LocationError> in
                    switch status {
                    case .authorizedWhenInUse, .authorizedAlways:
                        return .success(status)
                    case .denied, .restricted:
                        return .failure(.unauthorized)
                    case .notDetermined:
                        return .failure(.unauthorized)
                    @unknown default:
                        return .failure(.unauthorized)
                    }
                }
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { result in
                        switch result {
                        case .success(let status):
                            promise(.success(status))
                        case .failure(let error):
                            promise(.failure(error))
                        }
                    }
                )
                .store(in: &self!.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    /// Starts location updates with adaptive accuracy and battery optimization
    /// - Returns: Publisher streaming optimized location updates
    func startUpdatingLocation() -> AnyPublisher<Location, LocationError> {
        os_signpost(.begin, log: performanceLog, name: "LocationUpdates")
        
        locationLock.lock()
        defer { locationLock.unlock() }
        
        guard !isUpdating else {
            return locationPublisher.eraseToAnyPublisher()
        }
        
        isUpdating = true
        locationManager.startUpdatingLocation()
        
        // Monitor battery level for adaptive accuracy
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.adjustAccuracyForBatteryLevel()
            }
            .store(in: &cancellables)
        
        return locationPublisher
            .handleEvents(
                receiveCancel: { [weak self] in
                    self?.stopUpdatingLocation()
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Safely stops location updates with resource cleanup
    func stopUpdatingLocation() {
        os_signpost(.end, log: performanceLog, name: "LocationUpdates")
        
        locationLock.lock()
        defer { locationLock.unlock() }
        
        guard isUpdating else { return }
        
        locationManager.stopUpdatingLocation()
        isUpdating = false
        cancellables.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }
    
    /// Finds users within LiDAR range with precision validation
    /// - Parameters:
    ///   - radius: Search radius in meters
    ///   - requiredAccuracy: Minimum required location accuracy
    /// - Returns: Publisher streaming validated nearby locations
    func findNearbyUsers(radius: Double, requiredAccuracy: CLLocationAccuracy) -> AnyPublisher<[Location], LocationError> {
        guard radius >= LocationConstants.MIN_DETECTION_RANGE && radius <= LocationConstants.MAX_DETECTION_RANGE else {
            return Fail(error: .outOfRange).eraseToAnyPublisher()
        }
        
        guard let currentLocation = self.currentLocation else {
            return Fail(error: .locationServicesDisabled).eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            guard let self = self else { return }
            
            os_signpost(.begin, log: self.performanceLog, name: "NearbySearch")
            
            // Validate current location accuracy
            guard currentLocation.horizontalAccuracy <= requiredAccuracy else {
                promise(.failure(.invalidAccuracy))
                return
            }
            
            // Query nearby locations with spatial validation
            self.performNearbySearch(center: currentLocation, radius: radius)
                .sink(
                    receiveCompletion: { completion in
                        os_signpost(.end, log: self.performanceLog, name: "NearbySearch")
                        if case .failure(let error) = completion {
                            promise(.failure(error))
                        }
                    },
                    receiveValue: { locations in
                        promise(.success(locations))
                    }
                )
                .store(in: &self.cancellables)
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = LocationConstants.DESIRED_ACCURACY
        locationManager.distanceFilter = LocationConstants.LOCATION_UPDATE_INTERVAL
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = true
    }
    
    private func setupPerformanceMonitoring() {
        os_signpost(.begin, log: performanceLog, name: "PerformanceMonitoring")
    }
    
    private func adjustAccuracyForBatteryLevel() {
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel <= Float(LocationConstants.BATTERY_THRESHOLD) {
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        } else {
            locationManager.desiredAccuracy = LocationConstants.DESIRED_ACCURACY
        }
    }
    
    private func performNearbySearch(center: Location, radius: Double) -> AnyPublisher<[Location], LocationError> {
        // Implementation would integrate with spatial database
        // This is a placeholder that would be replaced with actual spatial query
        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let clLocation = locations.last else { return }
        
        locationLock.lock()
        defer { locationLock.unlock() }
        
        do {
            let location = try Location(
                coordinate: clLocation.coordinate,
                altitude: clLocation.altitude,
                spatialCoordinate: nil // Would be populated with LiDAR data
            )
            
            currentLocation = location
            locationPublisher.send(location)
            
        } catch {
            locationPublisher.send(completion: .failure(.precisionValidationFailed))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationPublisher.send(completion: .failure(.locationServicesDisabled))
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            locationPublisher.send(completion: .failure(.unauthorized))
        }
    }
}