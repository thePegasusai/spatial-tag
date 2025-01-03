//
// Location.swift
// SpatialTag
//
// Core location model with enhanced spatial awareness capabilities
// combining GPS coordinates with LiDAR-based positioning
//

import CoreLocation // iOS 15.0+
import simd // iOS 15.0+
import os.log // iOS 15.0+

// MARK: - Global Constants

private let MIN_DETECTION_RANGE: Double = 0.5 // Minimum detection range in meters
private let MAX_DETECTION_RANGE: Double = 50.0 // Maximum detection range in meters
private let LIDAR_PRECISION_THRESHOLD: Double = 10.0 // Precision threshold in meters
private let PERFORMANCE_THRESHOLD_MS: Double = 100.0 // Maximum allowed processing time

// MARK: - Error Types

enum LocationError: Error {
    case invalidCoordinate
    case invalidRange
    case invalidSpatialCoordinate
    case performanceThresholdExceeded
    case calculationError
}

// MARK: - Location Class

@objc
@objcMembers
class Location: NSObject {
    
    // MARK: - Properties
    
    private let lock = NSLock()
    private(set) var coordinate: CLLocationCoordinate2D
    private(set) var altitude: Double
    private(set) var spatialCoordinate: simd_float3?
    private(set) var timestamp: Date
    private(set) var horizontalAccuracy: Double
    private(set) var verticalAccuracy: Double
    private(set) var isVisible: Bool
    
    private let performanceLog = OSLog(subsystem: "com.spatialtag.location", category: "Performance")
    
    // MARK: - Initialization
    
    init(coordinate: CLLocationCoordinate2D, altitude: Double, spatialCoordinate: simd_float3? = nil) throws {
        guard coordinate.isValid() else {
            throw LocationError.invalidCoordinate
        }
        
        self.coordinate = coordinate
        self.altitude = altitude
        self.spatialCoordinate = spatialCoordinate
        self.timestamp = Date()
        self.horizontalAccuracy = 0.0
        self.verticalAccuracy = 0.0
        self.isVisible = true
        
        super.init()
        
        os_signpost(.begin, log: performanceLog, name: "LocationInitialization")
        updateAccuracyValues()
        os_signpost(.end, log: performanceLog, name: "LocationInitialization")
    }
    
    // MARK: - Public Methods
    
    func distanceTo(_ otherLocation: Location) -> Result<Double, LocationError> {
        let startTime = DispatchTime.now()
        
        guard coordinate.isValid() && otherLocation.coordinate.isValid() else {
            return .failure(.invalidCoordinate)
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        do {
            let distance: Double
            
            if let spatial = spatialCoordinate, let otherSpatial = otherLocation.spatialCoordinate {
                // Use LiDAR-based spatial coordinates for enhanced precision
                distance = simd_distance(spatial, otherSpatial)
            } else {
                // Fall back to GPS-based calculation
                let baseLocation = coordinate.toLocation()
                let otherBaseLocation = otherLocation.coordinate.toLocation()
                distance = baseLocation.adaptivePrecisionDistance(from: otherBaseLocation)
            }
            
            // Validate performance
            let endTime = DispatchTime.now()
            let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000 // Convert to milliseconds
            
            if elapsedTime > PERFORMANCE_THRESHOLD_MS {
                os_signpost(.event, log: performanceLog, name: "PerformanceWarning",
                           "Distance calculation exceeded threshold: %{public}f ms", elapsedTime)
            }
            
            guard distance >= MIN_DETECTION_RANGE && distance <= MAX_DETECTION_RANGE else {
                return .failure(.invalidRange)
            }
            
            return .success(distance)
        } catch {
            return .failure(.calculationError)
        }
    }
    
    func isWithinRange(_ range: Double) -> Bool {
        guard range > 0 && range <= MAX_DETECTION_RANGE else {
            return false
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        let baseLocation = coordinate.toLocation()
        return baseLocation.isWithinLiDARRange(from: baseLocation) && 
               baseLocation.isWithinRange(from: baseLocation, range: range)
    }
    
    func updateSpatialCoordinate(_ newCoordinate: simd_float3) -> Result<Void, LocationError> {
        let startTime = DispatchTime.now()
        
        // Validate spatial coordinate bounds
        let magnitude = simd_length(newCoordinate)
        guard magnitude >= Float(MIN_DETECTION_RANGE) && magnitude <= Float(MAX_DETECTION_RANGE) else {
            return .failure(.invalidSpatialCoordinate)
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        spatialCoordinate = newCoordinate
        timestamp = Date()
        updateAccuracyValues()
        
        let endTime = DispatchTime.now()
        let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        
        os_signpost(.event, log: performanceLog, name: "SpatialUpdate",
                   "Update completed in %{public}f ms", elapsedTime)
        
        return .success(())
    }
    
    // MARK: - Private Methods
    
    private func updateAccuracyValues() {
        if let spatial = spatialCoordinate {
            // Enhanced accuracy when LiDAR data is available
            let distance = simd_length(spatial)
            horizontalAccuracy = Double(distance) < LIDAR_PRECISION_THRESHOLD ? 0.01 : 0.1
            verticalAccuracy = horizontalAccuracy
        } else {
            // Standard GPS accuracy
            horizontalAccuracy = 5.0
            verticalAccuracy = 10.0
        }
    }
}

// MARK: - Equatable

extension Location: Equatable {
    static func == (lhs: Location, rhs: Location) -> Bool {
        return lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.altitude == rhs.altitude &&
               lhs.spatialCoordinate == rhs.spatialCoordinate
    }
}