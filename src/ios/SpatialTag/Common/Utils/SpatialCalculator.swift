//
// SpatialCalculator.swift
// SpatialTag
//
// Thread-safe core utility class for high-precision spatial calculations
// combining LiDAR and GPS data with comprehensive performance monitoring
//

import CoreLocation // iOS 15.0+
import simd // iOS 15.0+
import ARKit // 6.0
import os.signpost // iOS 15.0+

// MARK: - Global Constants

private let MIN_DETECTION_RANGE: Double = 0.5 // Minimum detection range in meters
private let MAX_DETECTION_RANGE: Double = 50.0 // Maximum detection range in meters
private let PRECISION_THRESHOLD: Double = 0.01 // ±1cm precision threshold
private let BATTERY_USAGE_THRESHOLD: Double = 0.15 // 15% maximum battery drain per hour
private let PERFORMANCE_THRESHOLD_MS: Double = 100.0 // Maximum processing time in milliseconds

private let DISTANCE_PRECISION_ADJUSTMENTS: [String: Double] = [
    "near": 0.01,   // ±1cm for close range
    "medium": 0.05, // ±5cm for medium range
    "far": 0.1      // ±10cm for far range
]

// MARK: - Error Types

enum SpatialError: Error {
    case invalidInput
    case outOfRange
    case lidarUnavailable
    case calculationError
    case performanceThresholdExceeded
    case batteryThresholdExceeded
}

// MARK: - SpatialCalculator Class

@available(iOS 15.0, *)
@objc
class SpatialCalculator: NSObject {
    
    // MARK: - Properties
    
    private var worldTransform: matrix_float4x4
    private let referenceLocation: CLLocation
    private let calculationLock = NSLock()
    
    private(set) var batteryImpact: Double = 0.0
    
    private let performanceLog = OSLog(subsystem: "com.spatialtag.spatial", category: "Performance")
    private let signpostID = OSSignpostID(log: .default)
    
    // MARK: - Initialization
    
    init(referenceLocation: CLLocation) {
        self.referenceLocation = referenceLocation
        self.worldTransform = matrix_identity_float4x4
        
        super.init()
        
        setupBatteryMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Calculates precise spatial distance between two locations using LiDAR with GPS fallback
    /// - Parameters:
    ///   - location1: First location
    ///   - location2: Second location
    ///   - useLiDAR: Flag to force LiDAR usage when available
    /// - Returns: Result containing distance in meters or error
    @objc
    func calculateSpatialDistance(location1: Location, location2: Location, useLiDAR: Bool = true) -> Result<Double, SpatialError> {
        os_signpost(.begin, log: performanceLog, name: "SpatialCalculation")
        let startTime = DispatchTime.now()
        
        // Thread safety
        calculationLock.lock()
        defer {
            calculationLock.unlock()
            os_signpost(.end, log: performanceLog, name: "SpatialCalculation")
        }
        
        do {
            // Validate inputs
            guard location1.coordinate.isValid(), location2.coordinate.isValid() else {
                throw SpatialError.invalidInput
            }
            
            // Calculate distance based on available data
            let distance: Double
            
            if useLiDAR,
               let spatial1 = location1.spatialCoordinate,
               let spatial2 = location2.spatialCoordinate {
                // Use LiDAR-based spatial coordinates for enhanced precision
                distance = calculateLiDARDistance(spatial1: spatial1, spatial2: spatial2)
            } else {
                // Fall back to GPS-based calculation with precision adjustments
                distance = calculateGPSDistance(location1: location1, location2: location2)
            }
            
            // Validate range
            guard distance >= MIN_DETECTION_RANGE && distance <= MAX_DETECTION_RANGE else {
                throw SpatialError.outOfRange
            }
            
            // Performance monitoring
            let endTime = DispatchTime.now()
            let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            if elapsedTime > PERFORMANCE_THRESHOLD_MS {
                os_signpost(.event, log: performanceLog, name: "PerformanceWarning",
                           "Distance calculation exceeded threshold: %{public}f ms", elapsedTime)
                throw SpatialError.performanceThresholdExceeded
            }
            
            // Battery impact monitoring
            if batteryImpact > BATTERY_USAGE_THRESHOLD {
                throw SpatialError.batteryThresholdExceeded
            }
            
            return .success(distance)
        } catch let error as SpatialError {
            return .failure(error)
        } catch {
            return .failure(.calculationError)
        }
    }
    
    /// Validates if location is within LiDAR detection range
    /// - Parameter location: Location to validate
    /// - Returns: Result indicating if location is in range
    @objc
    func isInDetectionRange(_ location: Location) -> Result<Bool, SpatialError> {
        calculationLock.lock()
        defer { calculationLock.unlock() }
        
        guard location.coordinate.isValid() else {
            return .failure(.invalidInput)
        }
        
        do {
            let distance = try calculateDistanceToReference(location)
            return .success(distance >= MIN_DETECTION_RANGE && distance <= MAX_DETECTION_RANGE)
        } catch {
            return .failure(.calculationError)
        }
    }
    
    // MARK: - Private Methods
    
    private func calculateLiDARDistance(spatial1: simd_float3, spatial2: simd_float3) -> Double {
        let distance = simd_distance(spatial1, spatial2)
        return applyPrecisionAdjustment(Double(distance))
    }
    
    private func calculateGPSDistance(location1: Location, location2: Location) -> Double {
        let baseLocation = CLLocation(latitude: location1.coordinate.latitude,
                                    longitude: location1.coordinate.longitude)
        let targetLocation = CLLocation(latitude: location2.coordinate.latitude,
                                      longitude: location2.coordinate.longitude)
        
        return baseLocation.adaptivePrecisionDistance(from: targetLocation)
    }
    
    private func calculateDistanceToReference(_ location: Location) throws -> Double {
        let result = calculateSpatialDistance(location1: Location(coordinate: referenceLocation.coordinate,
                                                                altitude: referenceLocation.altitude),
                                            location2: location)
        
        switch result {
        case .success(let distance):
            return distance
        case .failure(let error):
            throw error
        }
    }
    
    private func applyPrecisionAdjustment(_ distance: Double) -> Double {
        let adjustment: Double
        
        switch distance {
        case 0..<5:
            adjustment = DISTANCE_PRECISION_ADJUSTMENTS["near"]!
        case 5..<20:
            adjustment = DISTANCE_PRECISION_ADJUSTMENTS["medium"]!
        default:
            adjustment = DISTANCE_PRECISION_ADJUSTMENTS["far"]!
        }
        
        return round(distance / adjustment) * adjustment
    }
    
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(batteryLevelDidChange),
                                             name: UIDevice.batteryLevelDidChangeNotification,
                                             object: nil)
    }
    
    @objc
    private func batteryLevelDidChange(_ notification: Notification) {
        let currentLevel = UIDevice.current.batteryLevel
        if currentLevel > 0 {
            batteryImpact = 1.0 - currentLevel
        }
    }
    
    // MARK: - Deinitialization
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}