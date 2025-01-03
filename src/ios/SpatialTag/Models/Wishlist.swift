//
// Wishlist.swift
// SpatialTag
//
// Core model representing a user's wishlist with enhanced security
// and collaborative shopping features
//

import Foundation
import CryptoKit

// MARK: - Constants

private let MAX_WISHLIST_ITEMS = 100
private let MAX_SHARED_USERS = 10
private let PRICE_ENCRYPTION_KEY = SymmetricKey(size: .bits256)

// MARK: - Error Types

@objc public enum WishlistError: Int, Error {
    case itemLimitExceeded
    case invalidCurrency
    case encryptionFailed
    case sharingLimitExceeded
    case invalidOperation
    
    var localizedDescription: String {
        switch self {
        case .itemLimitExceeded:
            return "Maximum number of wishlist items exceeded"
        case .invalidCurrency:
            return "Invalid currency code provided"
        case .encryptionFailed:
            return "Failed to encrypt sensitive data"
        case .sharingLimitExceeded:
            return "Maximum number of shared users exceeded"
        case .invalidOperation:
            return "Invalid operation attempted"
        }
    }
}

// MARK: - WishlistItem Class

@objc
@objcMembers
public class WishlistItem: NSObject, Codable {
    public let id: UUID
    public let name: String
    public let description: String
    public private(set) var encryptedPrice: Data
    public let currency: String
    public var productUrl: URL?
    public var imageUrl: URL?
    public let addedDate: Date
    
    public init(id: UUID = UUID(),
               name: String,
               description: String = "",
               price: Double,
               currency: String) throws {
        self.id = id
        self.name = name
        self.description = description
        self.currency = currency.uppercased()
        self.addedDate = Date()
        
        // Validate currency format
        guard currency.count == 3 && currency == currency.uppercased() else {
            throw WishlistError.invalidCurrency
        }
        
        // Encrypt price data
        do {
            let priceData = withUnsafeBytes(of: price) { Data($0) }
            let sealedBox = try AES.GCM.seal(priceData, using: PRICE_ENCRYPTION_KEY)
            self.encryptedPrice = sealedBox.combined ?? Data()
        } catch {
            throw WishlistError.encryptionFailed
        }
        
        super.init()
    }
}

// MARK: - WishlistVisibility

@objc public enum WishlistVisibility: Int {
    case private = 0
    case shared = 1
    case public = 2
}

// MARK: - Wishlist Class

@objc
@objcMembers
public class Wishlist: NSObject {
    
    // MARK: - Properties
    
    public let id: UUID
    public let name: String
    public let ownerId: UUID
    public private(set) var sharedWithUserIds: [UUID]
    public private(set) var items: [WishlistItem]
    public private(set) var visibility: WishlistVisibility
    public let createdDate: Date
    public private(set) var lastModifiedDate: Date
    public var isShared: Bool { visibility != .private }
    
    private let lock = NSLock()
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    public init(id: UUID = UUID(),
               name: String,
               ownerId: UUID,
               visibility: WishlistVisibility = .private) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.visibility = visibility
        self.createdDate = Date()
        self.lastModifiedDate = Date()
        self.items = []
        self.sharedWithUserIds = []
        
        super.init()
        
        logger.debug("Wishlist initialized: \(id.uuidString)")
    }
    
    // MARK: - Item Management
    
    public func addItem(_ item: WishlistItem) -> Result<Bool, WishlistError> {
        lock.lock()
        defer { lock.unlock() }
        
        logger.debug("Adding item to wishlist \(id.uuidString): \(item.name)")
        
        guard items.count < MAX_WISHLIST_ITEMS else {
            logger.warning("Item limit exceeded for wishlist \(id.uuidString)")
            return .failure(.itemLimitExceeded)
        }
        
        items.append(item)
        lastModifiedDate = Date()
        
        logger.info("Item added to wishlist \(id.uuidString): \(item.id.uuidString)")
        return .success(true)
    }
    
    public func removeItem(withId itemId: UUID) -> Result<Bool, WishlistError> {
        lock.lock()
        defer { lock.unlock() }
        
        logger.debug("Removing item from wishlist \(id.uuidString): \(itemId.uuidString)")
        
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            logger.warning("Item not found in wishlist \(id.uuidString): \(itemId.uuidString)")
            return .failure(.invalidOperation)
        }
        
        items.remove(at: index)
        lastModifiedDate = Date()
        
        logger.info("Item removed from wishlist \(id.uuidString): \(itemId.uuidString)")
        return .success(true)
    }
    
    // MARK: - Sharing Management
    
    public func shareWith(userIds: [UUID]) -> Result<Bool, WishlistError> {
        lock.lock()
        defer { lock.unlock() }
        
        logger.debug("Sharing wishlist \(id.uuidString) with \(userIds.count) users")
        
        let uniqueUserIds = Set(userIds)
        let totalSharedUsers = Set(sharedWithUserIds).union(uniqueUserIds)
        
        guard totalSharedUsers.count <= MAX_SHARED_USERS else {
            logger.warning("Sharing limit exceeded for wishlist \(id.uuidString)")
            return .failure(.sharingLimitExceeded)
        }
        
        sharedWithUserIds = Array(totalSharedUsers)
        visibility = .shared
        lastModifiedDate = Date()
        
        logger.info("Wishlist \(id.uuidString) shared with \(userIds.count) users")
        return .success(true)
    }
}

// MARK: - Codable Conformance

extension Wishlist: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, ownerId, sharedWithUserIds, items
        case visibility, createdDate, lastModifiedDate
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(sharedWithUserIds, forKey: .sharedWithUserIds)
        try container.encode(items, forKey: .items)
        try container.encode(visibility.rawValue, forKey: .visibility)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lastModifiedDate, forKey: .lastModifiedDate)
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        sharedWithUserIds = try container.decode([UUID].self, forKey: .sharedWithUserIds)
        items = try container.decode([WishlistItem].self, forKey: .items)
        visibility = WishlistVisibility(rawValue: try container.decode(Int.self, forKey: .visibility)) ?? .private
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        lastModifiedDate = try container.decode(Date.self, forKey: .lastModifiedDate)
        
        super.init()
    }
}