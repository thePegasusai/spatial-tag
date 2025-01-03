//
// CommerceService.swift
// SpatialTag
//
// Enhanced service class managing commerce-related operations with
// improved security, performance, and real-time capabilities
//

import Foundation // iOS 15.0+
import Combine // iOS 15.0+

/// Enhanced commerce service managing wishlist operations and shared shopping experiences
@available(iOS 15.0, *)
public final class CommerceService {
    
    // MARK: - Constants
    
    private let MAX_SHARED_USERS = 10
    private let CACHE_EXPIRY_SECONDS = 300
    private let MAX_RETRY_ATTEMPTS = 3
    private let PERFORMANCE_THRESHOLD: TimeInterval = 1.0
    
    // MARK: - Properties
    
    private let apiClient: APIClient
    private let wishlistCache: NSCache<NSString, Wishlist>
    private let operationQueue: DispatchQueue
    private let logger = Logger.shared
    
    public let currentWishlist: CurrentValueSubject<Wishlist?, Never>
    public let wishlistUpdates: PassthroughSubject<WishlistUpdate, Never>
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init() {
        self.apiClient = APIClient.shared
        self.currentWishlist = CurrentValueSubject<Wishlist?, Never>(nil)
        self.wishlistUpdates = PassthroughSubject<WishlistUpdate, Never>()
        
        // Configure cache with size limits
        self.wishlistCache = NSCache<NSString, Wishlist>()
        wishlistCache.countLimit = 100
        wishlistCache.totalCostLimit = 10_485_760 // 10MB
        
        // Initialize operation queue with QoS
        self.operationQueue = DispatchQueue(label: "com.spatialtag.commerce",
                                          qos: .userInitiated,
                                          attributes: .concurrent)
        
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Fetches user's wishlist with enhanced caching and retry support
    /// - Parameter userId: User identifier
    /// - Returns: Publisher emitting wishlist data or error
    public func fetchWishlist(userId: UUID) -> AnyPublisher<Wishlist, Error> {
        let startTime = Date()
        
        // Check cache first
        if let cached = checkCache(for: userId) {
            logger.debug("Cache hit for wishlist: \(userId.uuidString)")
            return Just(cached)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return apiClient.request(endpoint: .commerce(.wishlist))
            .tryMap { (data: Wishlist) -> Wishlist in
                // Update cache
                self.updateCache(userId: userId, wishlist: data)
                
                // Update current wishlist
                self.currentWishlist.send(data)
                
                // Log performance
                let duration = Date().timeIntervalSince(startTime)
                self.logger.performance("Wishlist fetch",
                                     duration: duration,
                                     threshold: self.PERFORMANCE_THRESHOLD,
                                     metadata: ["userId": userId.uuidString])
                
                return data
            }
            .retry(MAX_RETRY_ATTEMPTS)
            .receive(on: operationQueue)
            .eraseToAnyPublisher()
    }
    
    /// Adds item to wishlist with optimistic updates and conflict resolution
    /// - Parameter item: Item to add
    /// - Returns: Publisher emitting updated wishlist
    public func addToWishlist(item: WishlistItem) -> AnyPublisher<Wishlist, Error> {
        guard var currentList = currentWishlist.value else {
            return Fail(error: APIError.invalidOperation)
                .eraseToAnyPublisher()
        }
        
        // Optimistic update
        let result = currentList.addItem(item)
        switch result {
        case .success:
            currentWishlist.send(currentList)
        case .failure(let error):
            return Fail(error: error)
                .eraseToAnyPublisher()
        }
        
        return apiClient.request(
            endpoint: .commerce(.addToWishlist),
            body: item
        )
        .tryMap { (data: Wishlist) -> Wishlist in
            // Update cache and current wishlist
            self.updateCache(userId: data.ownerId, wishlist: data)
            self.currentWishlist.send(data)
            
            // Emit update event
            self.wishlistUpdates.send(.itemAdded(item))
            
            return data
        }
        .catch { error -> AnyPublisher<Wishlist, Error> in
            // Revert optimistic update on failure
            self.currentWishlist.send(currentList)
            return Fail(error: error).eraseToAnyPublisher()
        }
        .receive(on: operationQueue)
        .eraseToAnyPublisher()
    }
    
    /// Shares wishlist with enhanced security validation
    /// - Parameter userIds: Users to share with
    /// - Returns: Publisher emitting shared wishlist status
    public func shareWishlist(with userIds: [UUID]) -> AnyPublisher<Wishlist, Error> {
        guard let currentList = currentWishlist.value else {
            return Fail(error: APIError.invalidOperation)
                .eraseToAnyPublisher()
        }
        
        // Validate sharing limits
        guard userIds.count + currentList.sharedWithUserIds.count <= MAX_SHARED_USERS else {
            return Fail(error: WishlistError.sharingLimitExceeded)
                .eraseToAnyPublisher()
        }
        
        return apiClient.request(
            endpoint: .commerce(.share),
            body: ["userIds": userIds]
        )
        .tryMap { (data: Wishlist) -> Wishlist in
            // Update cache and current wishlist
            self.updateCache(userId: data.ownerId, wishlist: data)
            self.currentWishlist.send(data)
            
            // Emit update event
            self.wishlistUpdates.send(.shared(userIds))
            
            return data
        }
        .receive(on: operationQueue)
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        NetworkMonitor.shared.networkStatus
            .sink { [weak self] status in
                if case .disconnected = status {
                    self?.wishlistCache.removeAllObjects()
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkCache(for userId: UUID) -> Wishlist? {
        let key = NSString(string: userId.uuidString)
        guard let cached = wishlistCache.object(forKey: key) else {
            return nil
        }
        
        // Validate cache freshness
        let cacheAge = Date().timeIntervalSince(cached.lastModifiedDate)
        guard cacheAge <= Double(CACHE_EXPIRY_SECONDS) else {
            wishlistCache.removeObject(forKey: key)
            return nil
        }
        
        return cached
    }
    
    private func updateCache(userId: UUID, wishlist: Wishlist) {
        let key = NSString(string: userId.uuidString)
        wishlistCache.setObject(wishlist, forKey: key)
    }
}

// MARK: - WishlistUpdate Enum

/// Represents wishlist update events for real-time synchronization
public enum WishlistUpdate {
    case itemAdded(WishlistItem)
    case itemRemoved(UUID)
    case shared([UUID])
    case updated(Wishlist)
}