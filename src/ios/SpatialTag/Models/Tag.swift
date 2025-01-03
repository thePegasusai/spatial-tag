//
// Tag.swift
// SpatialTag
//
// Core model representing a digital tag in the Spatial Tag application
// with thread-safe operations and performance optimizations
//

import Foundation // iOS 15.0+
import os.log // iOS 15.0+

// MARK: - Global Constants

private let DEFAULT_VISIBILITY_RADIUS: Double = 50.0
private let DEFAULT_EXPIRATION_HOURS: Double = 24.0
private let MAX_CONTENT_LENGTH: Int = 1000
private let MIN_VISIBILITY_RADIUS: Double = 1.0
private let MAX_VISIBILITY_RADIUS: Double = 100.0
private let INTERACTION_THRESHOLD: Int = 1000

// MARK: - Error Types

enum TagError: Error {
    case invalidContent
    case invalidLocation
    case invalidRadius
    case invalidCreator
    case expirationError
    case serializationError
}

// MARK: - Supporting Types

@propertyWrapper
struct Atomic<T> {
    private let lock = NSLock()
    private var value: T
    
    init(wrappedValue: T) {
        self.value = wrappedValue
    }
    
    var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

enum VisibilityState: Int, Codable {
    case visible
    case hidden
    case expired
}

struct TagMetrics: Codable {
    var totalInteractions: Int
    var lastInteractionDate: Date?
    var creationTimestamp: Date
    var performanceMetrics: [String: Double]
}

// MARK: - Tag Structure

public struct Tag {
    // MARK: - Properties
    
    public let id: UUID
    public let creatorId: UUID
    public let location: Location
    public let content: String
    public let visibilityRadius: Double
    public let createdAt: Date
    public let expiresAt: Date
    
    @Atomic private var isVisible: Bool = true
    @Atomic private var interactionCount: Int = 0
    private var lastInteractionDate: Date?
    private var visibilityState: VisibilityState = .visible
    private var metrics: TagMetrics
    
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    public init(creatorId: UUID, 
               location: Location, 
               content: String, 
               visibilityRadius: Double? = nil,
               expirationHours: TimeInterval? = nil) throws {
        
        // Validate content
        guard !content.isEmpty && content.count <= MAX_CONTENT_LENGTH else {
            throw TagError.invalidContent
        }
        
        // Validate location
        guard location.coordinate.isValid() else {
            throw TagError.invalidLocation
        }
        
        // Set properties
        self.id = UUID()
        self.creatorId = creatorId
        self.location = location
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate and set visibility radius
        let radius = visibilityRadius ?? DEFAULT_VISIBILITY_RADIUS
        guard radius >= MIN_VISIBILITY_RADIUS && radius <= MAX_VISIBILITY_RADIUS else {
            throw TagError.invalidRadius
        }
        self.visibilityRadius = radius
        
        // Set timestamps
        self.createdAt = Date()
        let expiration = expirationHours ?? DEFAULT_EXPIRATION_HOURS
        self.expiresAt = Calendar.current.date(byAdding: .hour, 
                                             value: Int(expiration), 
                                             to: createdAt) ?? Date()
        
        // Initialize metrics
        self.metrics = TagMetrics(
            totalInteractions: 0,
            lastInteractionDate: nil,
            creationTimestamp: createdAt,
            performanceMetrics: [:]
        )
        
        logger.debug("Tag created: \(id.uuidString)")
    }
    
    // MARK: - Public Methods
    
    public func isExpired() -> Bool {
        let now = Date()
        let expired = now >= expiresAt
        
        if expired {
            logger.debug("Tag expired: \(id.uuidString)")
        }
        
        return expired
    }
    
    public func isWithinRange(_ userLocation: Location) -> Bool {
        let startTime = DispatchTime.now()
        
        guard !isExpired() else {
            return false
        }
        
        let result = location.distanceTo(userLocation)
        switch result {
        case .success(let distance):
            let withinRange = distance <= visibilityRadius
            
            // Record performance metrics
            let endTime = DispatchTime.now()
            let elapsedTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            metrics.performanceMetrics["rangeCheck"] = elapsedTime
            
            return withinRange
            
        case .failure(let error):
            logger.error("Range check failed: \(error)")
            return false
        }
    }
    
    public mutating func recordInteraction() {
        let now = Date()
        
        interactionCount += 1
        lastInteractionDate = now
        metrics.totalInteractions = interactionCount
        metrics.lastInteractionDate = now
        
        if interactionCount >= INTERACTION_THRESHOLD {
            logger.info("High interaction tag: \(id.uuidString)")
        }
        
        logger.debug("Interaction recorded for tag: \(id.uuidString)")
    }
    
    public func toJSON() -> Result<[String: Any], TagError> {
        do {
            var json: [String: Any] = [
                "id": id.uuidString,
                "creatorId": creatorId.uuidString,
                "content": content,
                "visibilityRadius": visibilityRadius,
                "createdAt": ISO8601DateFormatter().string(from: createdAt),
                "expiresAt": ISO8601DateFormatter().string(from: expiresAt),
                "isVisible": isVisible,
                "interactionCount": interactionCount,
                "visibilityState": visibilityState.rawValue
            ]
            
            if let lastInteraction = lastInteractionDate {
                json["lastInteractionDate"] = ISO8601DateFormatter().string(from: lastInteraction)
            }
            
            // Add location data
            if let locationData = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(location)) {
                json["location"] = locationData
            }
            
            // Add metrics
            if let metricsData = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics)) {
                json["metrics"] = metricsData
            }
            
            return .success(json)
            
        } catch {
            logger.error("JSON serialization failed: \(error.localizedDescription)")
            return .failure(.serializationError)
        }
    }
}

// MARK: - Equatable Conformance

extension Tag: Equatable {
    public static func == (lhs: Tag, rhs: Tag) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Codable Conformance

extension Tag: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, creatorId, location, content, visibilityRadius
        case createdAt, expiresAt, isVisible, interactionCount
        case lastInteractionDate, visibilityState, metrics
    }
}