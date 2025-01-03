// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// Thread-safe ViewModel managing wishlist state, user interactions, and secure collaborative features
@MainActor
final class WishlistViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var wishlist: Wishlist?
    @Published private(set) var items: [WishlistItem] = []
    @Published private(set) var visibility: WishlistVisibility = .private
    @Published private(set) var isShared: Bool = false
    @Published private(set) var sharedWithUsers: [UUID] = []
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private let commerceService: CommerceService
    private let userId: UUID
    private let itemCache: NSCache<NSString, WishlistItem>
    private let lastSyncTimestamp = CurrentValueSubject<Date?, Never>(nil)
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger.shared
    private let lock = NSLock()
    
    // MARK: - Constants
    
    private enum Constants {
        static let cacheLimit = 100
        static let cacheCostLimit = 5 * 1024 * 1024 // 5MB
        static let syncInterval: TimeInterval = 30.0
        static let performanceThreshold: TimeInterval = 0.1
    }
    
    // MARK: - Initialization
    
    init(commerceService: CommerceService, userId: UUID) {
        self.commerceService = commerceService
        self.userId = userId
        
        // Configure cache with limits
        self.itemCache = NSCache<NSString, WishlistItem>()
        itemCache.countLimit = Constants.cacheLimit
        itemCache.totalCostLimit = Constants.cacheCostLimit
        
        setupBindings()
        setupSyncTimer()
        
        logger.debug("WishlistViewModel initialized for user: \(userId.uuidString)")
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        fetchWishlist()
    }
    
    func onDisappear() {
        cancellables.removeAll()
    }
    
    /// Fetches wishlist data with caching and performance optimization
    func fetchWishlist() {
        let startTime = Date()
        
        Task {
            do {
                isLoading = true
                
                // Check cache first
                if let cached = checkCache() {
                    await updateWishlistState(cached)
                    logger.debug("Using cached wishlist data")
                    return
                }
                
                // Fetch from service with retry policy
                let publisher = commerceService.fetchWishlist(userId: userId)
                    .retry(3)
                    .receive(on: DispatchQueue.main)
                
                for try await wishlist in publisher.values {
                    await updateWishlistState(wishlist)
                    updateCache(wishlist)
                }
                
                // Log performance metrics
                let duration = Date().timeIntervalSince(startTime)
                logger.performance("Wishlist fetch",
                                duration: duration,
                                threshold: Constants.performanceThreshold,
                                metadata: ["userId": userId.uuidString])
                
            } catch {
                handleError(error)
                logger.error("Failed to fetch wishlist: \(error.localizedDescription)")
            }
            
            isLoading = false
        }
    }
    
    /// Adds item to wishlist with validation and sync
    func addItem(_ item: WishlistItem) async throws {
        let startTime = Date()
        
        do {
            isLoading = true
            
            // Validate item data
            guard validateItem(item) else {
                throw WishlistError.invalidOperation
            }
            
            // Optimistic update
            lock.lock()
            items.append(item)
            lock.unlock()
            
            // Update through service
            let publisher = commerceService.addToWishlist(item)
                .retry(2)
                .receive(on: DispatchQueue.main)
            
            for try await updatedWishlist in publisher.values {
                await updateWishlistState(updatedWishlist)
                updateCache(updatedWishlist)
                
                // Trigger sync for shared wishlists
                if isShared {
                    try await syncWishlist()
                }
            }
            
            // Log performance
            let duration = Date().timeIntervalSince(startTime)
            logger.performance("Add wishlist item",
                            duration: duration,
                            threshold: Constants.performanceThreshold,
                            metadata: ["itemId": item.id.uuidString])
            
        } catch {
            // Revert optimistic update
            lock.lock()
            items.removeAll { $0.id == item.id }
            lock.unlock()
            
            handleError(error)
            throw error
        }
        
        isLoading = false
    }
    
    /// Shares wishlist with enhanced security validation
    func shareWishlist(with userIds: [UUID]) async throws {
        let startTime = Date()
        
        do {
            isLoading = true
            
            // Validate sharing permissions
            guard let wishlist = wishlist else {
                throw WishlistError.invalidOperation
            }
            
            // Security validation
            try await validateSharingPermissions(userIds)
            
            let publisher = commerceService.shareWishlist(with: userIds)
                .retry(2)
                .receive(on: DispatchQueue.main)
            
            for try await updatedWishlist in publisher.values {
                await updateWishlistState(updatedWishlist)
                updateCache(updatedWishlist)
            }
            
            // Log performance
            let duration = Date().timeIntervalSince(startTime)
            logger.performance("Share wishlist",
                            duration: duration,
                            threshold: Constants.performanceThreshold,
                            metadata: ["recipientCount": userIds.count])
            
        } catch {
            handleError(error)
            throw error
        }
        
        isLoading = false
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Monitor wishlist updates
        commerceService.wishlistUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handleWishlistUpdate(update)
            }
            .store(in: &cancellables)
    }
    
    private func setupSyncTimer() {
        // Periodic sync for shared wishlists
        Timer.publish(every: Constants.syncInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isShared else { return }
                Task {
                    try? await self.syncWishlist()
                }
            }
            .store(in: &cancellables)
    }
    
    private func syncWishlist() async throws {
        guard isShared else { return }
        
        let publisher = commerceService.syncWishlist()
            .retry(2)
            .receive(on: DispatchQueue.main)
        
        for try await updatedWishlist in publisher.values {
            await updateWishlistState(updatedWishlist)
            updateCache(updatedWishlist)
            lastSyncTimestamp.send(Date())
        }
    }
    
    @MainActor
    private func updateWishlistState(_ wishlist: Wishlist) {
        self.wishlist = wishlist
        self.items = wishlist.items
        self.visibility = wishlist.visibility
        self.isShared = !wishlist.sharedWithUserIds.isEmpty
        self.sharedWithUsers = wishlist.sharedWithUserIds
    }
    
    private func validateItem(_ item: WishlistItem) -> Bool {
        guard !item.name.isEmpty else { return false }
        guard item.encryptedPrice.count > 0 else { return false }
        return true
    }
    
    private func validateSharingPermissions(_ userIds: [UUID]) async throws {
        try await commerceService.validateSharing(userIds: userIds)
    }
    
    private func checkCache() -> Wishlist? {
        let key = NSString(string: userId.uuidString)
        return itemCache.object(forKey: key) as? Wishlist
    }
    
    private func updateCache(_ wishlist: Wishlist) {
        let key = NSString(string: userId.uuidString)
        itemCache.setObject(wishlist, forKey: key)
    }
    
    private func handleWishlistUpdate(_ update: WishlistUpdate) {
        switch update {
        case .itemAdded(let item):
            lock.lock()
            items.append(item)
            lock.unlock()
        case .itemRemoved(let itemId):
            lock.lock()
            items.removeAll { $0.id == itemId }
            lock.unlock()
        case .updated(let wishlist):
            Task { @MainActor in
                await updateWishlistState(wishlist)
            }
        case .shared(let userIds):
            sharedWithUsers = userIds
            isShared = true
        }
    }
}

// MARK: - Error Handling

extension WishlistViewModel {
    private func handleError(_ error: Error) {
        self.error = error
        isLoading = false
        
        logger.error("WishlistViewModel error: \(error.localizedDescription)",
                    metadata: ["userId": userId.uuidString])
    }
}