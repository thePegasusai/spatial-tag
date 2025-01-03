// Foundation - iOS 15.0+ - Core iOS functionality
import Foundation

/// Logger for status level transitions and calculations
private let logger = Logger.shared

/// Constants for status level thresholds
private let ELITE_THRESHOLD: Int = 500
private let RARE_THRESHOLD: Int = 1000

/// Represents user status levels in the Spatial Tag platform
@objc public enum StatusLevel: Int, CustomStringConvertible {
    /// Regular status - default level for new users
    case regular = 0
    
    /// Elite status - achieved at 500+ points
    case elite = 1
    
    /// Rare status - achieved at 1000+ points
    case rare = 2
    
    /// Creates a StatusLevel based on point value
    /// - Parameter points: The user's current point total
    /// - Returns: The appropriate StatusLevel for the given points
    public static func fromPoints(_ points: Int) -> StatusLevel {
        precondition(points >= 0, "Points cannot be negative")
        
        logger.debug("Calculating status level for \(points) points")
        
        let status: StatusLevel
        if points >= RARE_THRESHOLD {
            status = .rare
        } else if points >= ELITE_THRESHOLD {
            status = .elite
        } else {
            status = .regular
        }
        
        logger.debug("Determined status level: \(status.description)")
        return status
    }
    
    /// The next status level in the progression
    public var nextLevel: StatusLevel? {
        switch self {
        case .regular:
            return .elite
        case .elite:
            return .rare
        case .rare:
            return nil
        }
    }
    
    /// Calculates points needed to reach the next level
    /// - Parameter currentPoints: User's current point total
    /// - Returns: Points needed for next level, or nil if at max level
    public func pointsToNextLevel(currentPoints: Int) -> Int? {
        guard let next = nextLevel else {
            return nil
        }
        
        return max(0, next.pointThreshold - currentPoints)
    }
    
    /// Human-readable description of the status level
    public var description: String {
        switch self {
        case .regular:
            return "Regular"
        case .elite:
            return "Elite"
        case .rare:
            return "Rare"
        }
    }
    
    /// Point threshold required to achieve this status level
    public var pointThreshold: Int {
        switch self {
        case .regular:
            return 0
        case .elite:
            return ELITE_THRESHOLD
        case .rare:
            return RARE_THRESHOLD
        }
    }
    
    /// Indicates if this is the highest possible status level
    public var isMaxLevel: Bool {
        return self == .rare
    }
}

// MARK: - Comparable Conformance
extension StatusLevel: Comparable {
    public static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Codable Conformance
extension StatusLevel: Codable {}