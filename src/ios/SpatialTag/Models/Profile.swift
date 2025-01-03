//
// Profile.swift
// SpatialTag
//
// Core model representing a user's profile with status, location tracking,
// and discovery settings for the Spatial Tag platform
//

import Foundation

// MARK: - Constants

private let VISIBILITY_RADIUS_DEFAULT: Double = 50.0
private let POINTS_EXPIRY_DAYS: Int = 90

// MARK: - Error Types

enum PreferenceError: Error {
    case invalidKey
    case invalidValue
    case validationFailed
}

// MARK: - Point Entry Structure

struct PointEntry: Codable {
    let points: Int
    let timestamp: Date
    let source: String
}

// MARK: - Profile Class

@objc
@objcMembers
public class Profile: NSObject {
    
    // MARK: - Properties
    
    public let id: UUID
    public var displayName: String
    public private(set) var statusLevel: StatusLevel
    public private(set) var lastLocation: Location?
    public private(set) var points: Int
    public private(set) var visibilityRadius: Double
    public private(set) var isVisible: Bool
    public private(set) var lastActive: Date
    public private(set) var preferences: [String: Any]
    private var pointHistory: [PointEntry]
    
    private let logger = Logger.shared
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(id: UUID, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.statusLevel = .regular
        self.lastLocation = nil
        self.points = 0
        self.visibilityRadius = VISIBILITY_RADIUS_DEFAULT
        self.isVisible = true
        self.lastActive = Date()
        self.preferences = [:]
        self.pointHistory = []
        
        super.init()
        
        logger.debug("Profile initialized: \(id.uuidString)")
    }
    
    // MARK: - Location Management
    
    public func updateLocation(_ newLocation: Location) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard newLocation.coordinate.isValid() else {
            logger.warning("Invalid location coordinates for profile: \(id.uuidString)")
            return false
        }
        
        lastLocation = newLocation
        lastActive = Date()
        
        logger.debug("Location updated for profile \(id.uuidString): \(newLocation.coordinate)")
        return true
    }
    
    // MARK: - Points and Status Management
    
    public func addPoints(_ newPoints: Int) -> StatusLevel {
        lock.lock()
        defer { lock.unlock() }
        
        // Create new point entry
        let entry = PointEntry(points: newPoints,
                             timestamp: Date(),
                             source: "interaction")
        pointHistory.append(entry)
        
        // Remove expired points
        let expiryDate = Calendar.current.date(byAdding: .day,
                                             value: -POINTS_EXPIRY_DAYS,
                                             to: Date()) ?? Date()
        pointHistory.removeAll { $0.timestamp < expiryDate }
        
        // Calculate total valid points
        points = pointHistory.reduce(0) { $0 + $1.points }
        
        // Update status level
        let newStatus = StatusLevel.fromPoints(points)
        if newStatus != statusLevel {
            logger.info("Status level changed for profile \(id.uuidString): \(statusLevel) -> \(newStatus)")
            statusLevel = newStatus
        }
        
        logger.debug("Points updated for profile \(id.uuidString): \(points) (added: \(newPoints))")
        return statusLevel
    }
    
    // MARK: - Preferences Management
    
    public func updatePreferences(_ newPreferences: [String: Any]) -> Result<Void, PreferenceError> {
        lock.lock()
        defer { lock.unlock() }
        
        // Validate preference keys and values
        for (key, value) in newPreferences {
            guard key.count <= 50 else {
                return .failure(.invalidKey)
            }
            
            guard value is String || value is Int || value is Double || value is Bool else {
                return .failure(.invalidValue)
            }
        }
        
        // Update preferences
        preferences.merge(newPreferences) { _, new in new }
        
        logger.debug("Preferences updated for profile \(id.uuidString)")
        return .success(())
    }
    
    // MARK: - Visibility Management
    
    public func updateVisibility(visible: Bool, radius: Double? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        isVisible = visible
        
        if let radius = radius {
            visibilityRadius = min(max(radius, 0.5), VISIBILITY_RADIUS_DEFAULT)
        }
        
        logger.debug("Visibility updated for profile \(id.uuidString): visible=\(visible), radius=\(visibilityRadius)")
    }
}

// MARK: - Codable Conformance

extension Profile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, statusLevel, lastLocation, points
        case visibilityRadius, isVisible, lastActive, preferences, pointHistory
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(statusLevel, forKey: .statusLevel)
        try container.encode(lastLocation, forKey: .lastLocation)
        try container.encode(points, forKey: .points)
        try container.encode(visibilityRadius, forKey: .visibilityRadius)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(lastActive, forKey: .lastActive)
        try container.encode(pointHistory, forKey: .pointHistory)
        
        // Encode preferences as JSON data
        let preferencesData = try JSONSerialization.data(withJSONObject: preferences)
        try container.encode(preferencesData, forKey: .preferences)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        statusLevel = try container.decode(StatusLevel.self, forKey: .statusLevel)
        lastLocation = try container.decodeIfPresent(Location.self, forKey: .lastLocation)
        points = try container.decode(Int.self, forKey: .points)
        visibilityRadius = try container.decode(Double.self, forKey: .visibilityRadius)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        lastActive = try container.decode(Date.self, forKey: .lastActive)
        pointHistory = try container.decode([PointEntry].self, forKey: .pointHistory)
        
        // Decode preferences from JSON data
        let preferencesData = try container.decode(Data.self, forKey: .preferences)
        preferences = try JSONSerialization.jsonObject(with: preferencesData) as? [String: Any] ?? [:]
        
        super.init()
    }
}