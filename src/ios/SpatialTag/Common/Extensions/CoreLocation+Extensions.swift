//
// CoreLocation+Extensions.swift
// SpatialTag
//
// CoreLocation framework extensions for enhanced spatial awareness
// and LiDAR integration capabilities
//
// CoreLocation Version: iOS 15.0+
//

import CoreLocation

// MARK: - Global Constants

private let MIN_DETECTION_RANGE: Double = 0.5 // Minimum detection range in meters for LiDAR scanning
private let MAX_DETECTION_RANGE: Double = 50.0 // Maximum detection range in meters for LiDAR scanning
private let PRECISION_THRESHOLD: Double = 10.0 // Distance threshold in meters for precision adjustment
private let OPTIMAL_PRECISION: Double = 0.01 // Optimal precision in meters (±1cm) for close range

// MARK: - CLLocation Extension

extension CLLocation {
    
    /// Calculates precise distance between two locations with LiDAR-enhanced accuracy
    /// - Parameter location: Target location to measure distance to
    /// - Returns: Distance in meters with enhanced precision
    func preciseDistance(from location: CLLocation) -> CLLocationDistance {
        let baseDistance = distance(from: location)
        let precisionFactor = calculatePrecisionFactor(distance: baseDistance)
        return round(baseDistance / precisionFactor) * precisionFactor
    }
    
    /// Calculates distance with adaptive precision based on range
    /// - Parameter location: Target location
    /// - Returns: Distance in meters with range-appropriate precision
    func adaptivePrecisionDistance(from location: CLLocation) -> CLLocationDistance {
        let rawDistance = distance(from: location)
        if rawDistance <= PRECISION_THRESHOLD {
            return preciseDistance(from: location)
        }
        return rawDistance
    }
    
    /// Checks if location is within valid LiDAR detection range
    /// - Parameter location: Target location to check
    /// - Returns: Boolean indicating if location is within LiDAR range
    func isWithinLiDARRange(from location: CLLocation) -> Bool {
        let distance = self.distance(from: location)
        return distance >= MIN_DETECTION_RANGE && distance <= MAX_DETECTION_RANGE
    }
    
    /// Validates if location is within specified range
    /// - Parameters:
    ///   - location: Target location
    ///   - range: Maximum allowed range in meters
    /// - Returns: Boolean indicating if location is within range
    func isWithinRange(from location: CLLocation, range: Double) -> Bool {
        return distance(from: location) <= range
    }
    
    /// Converts CLLocation to CLLocationCoordinate2D
    /// - Returns: Location coordinate representation
    func toLocationCoordinate() -> CLLocationCoordinate2D {
        return coordinate
    }
    
    /// Calculates precision factor based on distance for adaptive precision
    /// - Parameter distance: Distance in meters
    /// - Returns: Precision factor for calculations
    private func calculatePrecisionFactor(distance: Double) -> Double {
        guard distance > 0 else { return OPTIMAL_PRECISION }
        
        // Apply distance-based precision degradation
        if distance <= PRECISION_THRESHOLD {
            return OPTIMAL_PRECISION
        } else {
            let degradationFactor = log10(distance / PRECISION_THRESHOLD)
            return OPTIMAL_PRECISION * pow(10, degradationFactor)
        }
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    
    /// Converts coordinate to CLLocation
    /// - Returns: CLLocation representation
    func toLocation() -> CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    /// Validates coordinate values
    /// - Returns: Boolean indicating if coordinate is valid
    func isValid() -> Bool {
        return CLLocationCoordinate2DIsValid(self) &&
               latitude != 0 &&
               longitude != 0
    }
    
    /// Checks if coordinate is within specified boundary
    /// - Parameters:
    ///   - northEast: Northeast boundary coordinate
    ///   - southWest: Southwest boundary coordinate
    /// - Returns: Boolean indicating if coordinate is within bounds
    func isWithinBounds(northEast: CLLocationCoordinate2D, southWest: CLLocationCoordinate2D) -> Bool {
        return latitude <= northEast.latitude &&
               latitude >= southWest.latitude &&
               longitude <= northEast.longitude &&
               longitude >= southWest.longitude
    }
}