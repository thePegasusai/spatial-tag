//
// ProductDetailViewModel.swift
// SpatialTag
//
// Enhanced ViewModel for managing product detail view state and interactions
// with secure commerce operations and performance optimization
//

import Foundation // iOS 15.0+
import Combine // iOS 15.0+

/// ViewModel responsible for managing product detail view state and interactions
/// with enhanced security and performance features
@MainActor
public final class ProductDetailViewModel: ViewModelProtocol {
    
    // MARK: - Published Properties
    
    @Published private(set) var product: WishlistItem
    @Published private(set) var isInWishlist: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Private Properties
    
    private let commerceService: CommerceService
    private var cancellables = Set<AnyCancellable>()
    private let operationQueue: DispatchQueue
    private let performanceMonitor: PerformanceMonitor
    private let logger = Logger.shared
    
    // Rate limiting for wishlist operations
    private let wishlistRateLimiter: RateLimiter
    private let RATE_LIMIT_WINDOW: TimeInterval = 60
    private let MAX_OPERATIONS_PER_WINDOW = 10
    
    // Cache configuration
    private let cache: NSCache<NSString, WishlistItem>
    private let CACHE_EXPIRY_SECONDS: TimeInterval = 300
    
    // MARK: - Initialization
    
    /// Initializes the product detail view model with enhanced security context
    /// - Parameters:
    ///   - product: The wishlist item to display
    ///   - commerceService: Service for handling commerce operations
    public init(product: WishlistItem, commerceService: CommerceService) {
        self.product = product
        self.commerceService = commerceService
        
        // Initialize operation queue with QoS
        self.operationQueue = DispatchQueue(label: "com.spatialtag.productdetail",
                                          qos: .userInitiated,
                                          attributes: .concurrent)
        
        // Initialize performance monitoring
        self.performanceMonitor = PerformanceMonitor()
        
        // Configure rate limiter
        self.wishlistRateLimiter = RateLimiter(limit: MAX_OPERATIONS_PER_WINDOW,
                                              window: RATE_LIMIT_WINDOW)
        
        // Initialize cache with size limits
        self.cache = NSCache<NSString, WishlistItem>()
        cache.countLimit = 100
        cache.totalCostLimit = 5_242_880 // 5MB
        
        // Setup initial state
        setupInitialState()
    }
    
    // MARK: - Public Methods
    
    /// Toggles the product's wishlist status with rate limiting and retry logic
    /// - Returns: Publisher emitting success status with enhanced error handling
    public func toggleWishlistStatus() -> AnyPublisher<Bool, Error> {
        // Check rate limiting
        guard wishlistRateLimiter.shouldAllowRequest() else {
            return Fail(error: APIError.rateLimitExceeded(retryAfter: wishlistRateLimiter.timeUntilReset))
                .eraseToAnyPublisher()
        }
        
        let startTime = Date()
        isLoading = true
        
        let operation = isInWishlist ? 
            commerceService.removeFromWishlist(product.id) :
            commerceService.addToWishlist(product)
        
        return operation
            .handleEvents(receiveOutput: { [weak self] success in
                guard let self = self else { return }
                
                self.isInWishlist.toggle()
                self.updateCache()
                
                // Log performance metrics
                let duration = Date().timeIntervalSince(startTime)
                self.logger.performance("Wishlist operation",
                                     duration: duration,
                                     threshold: 1.0,
                                     metadata: [
                                        "productId": self.product.id.uuidString,
                                        "operation": self.isInWishlist ? "add" : "remove"
                                     ])
            }, receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                
                if case .failure(let error) = completion {
                    self?.error = error
                }
            })
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    /// Shares product details with other users using secure channels
    /// - Parameters:
    ///   - userIds: Array of user IDs to share with
    ///   - options: Sharing options configuration
    /// - Returns: Publisher indicating share completion with security validation
    public func shareProduct(with userIds: [UUID], options: ShareOptions) -> AnyPublisher<Bool, Error> {
        let startTime = Date()
        isLoading = true
        
        // Encrypt product data for sharing
        guard let encryptedData = try? commerceService.encryptProductData(product) else {
            return Fail(error: APIError.invalidOperation)
                .eraseToAnyPublisher()
        }
        
        // Validate share request
        return commerceService.validateShareRequest(userIds: userIds)
            .flatMap { [weak self] isValid -> AnyPublisher<Bool, Error> in
                guard let self = self, isValid else {
                    return Fail(error: APIError.forbidden)
                        .eraseToAnyPublisher()
                }
                
                return self.commerceService.shareWishlist(with: userIds)
                    .map { _ in true }
                    .handleEvents(receiveCompletion: { [weak self] completion in
                        self?.isLoading = false
                        
                        if case .failure(let error) = completion {
                            self?.error = error
                        }
                        
                        // Log performance metrics
                        let duration = Date().timeIntervalSince(startTime)
                        self?.logger.performance("Product share",
                                              duration: duration,
                                              threshold: 1.0,
                                              metadata: [
                                                "productId": self?.product.id.uuidString ?? "",
                                                "recipientCount": userIds.count
                                              ])
                    })
                    .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - ViewModelProtocol Implementation
    
    public func onAppear() {
        setupSubscriptions()
        checkWishlistStatus()
    }
    
    public func onDisappear() {
        cancellables.removeAll()
    }
    
    public func clearError() {
        error = nil
    }
    
    // MARK: - Private Methods
    
    private func setupInitialState() {
        // Check cache for existing state
        if let cachedProduct = checkCache() {
            self.product = cachedProduct
        }
        
        checkWishlistStatus()
    }
    
    private func setupSubscriptions() {
        // Monitor wishlist updates
        commerceService.wishlistUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handleWishlistUpdate(update)
            }
            .store(in: &cancellables)
    }
    
    private func checkWishlistStatus() {
        commerceService.fetchWishlist(userId: product.id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = error
                }
            } receiveValue: { [weak self] wishlist in
                self?.isInWishlist = wishlist.items.contains { $0.id == self?.product.id }
            }
            .store(in: &cancellables)
    }
    
    private func handleWishlistUpdate(_ update: WishlistUpdate) {
        switch update {
        case .itemAdded(let item):
            if item.id == product.id {
                isInWishlist = true
            }
        case .itemRemoved(let id):
            if id == product.id {
                isInWishlist = false
            }
        case .updated(let wishlist):
            isInWishlist = wishlist.items.contains { $0.id == product.id }
        default:
            break
        }
    }
    
    private func checkCache() -> WishlistItem? {
        let key = NSString(string: product.id.uuidString)
        guard let cached = cache.object(forKey: key) else {
            return nil
        }
        
        // Validate cache freshness
        let cacheAge = Date().timeIntervalSince(cached.addedDate)
        guard cacheAge <= CACHE_EXPIRY_SECONDS else {
            cache.removeObject(forKey: key)
            return nil
        }
        
        return cached
    }
    
    private func updateCache() {
        let key = NSString(string: product.id.uuidString)
        cache.setObject(product, forKey: key)
    }
}

// MARK: - Helper Types

/// Options for product sharing configuration
public struct ShareOptions {
    let allowResharing: Bool
    let expirationDate: Date?
    let notifyRecipients: Bool
    
    public init(allowResharing: Bool = false,
               expirationDate: Date? = nil,
               notifyRecipients: Bool = true) {
        self.allowResharing = allowResharing
        self.expirationDate = expirationDate
        self.notifyRecipients = notifyRecipients
    }
}

/// Performance monitoring for commerce operations
private final class PerformanceMonitor {
    private var metrics: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.spatialtag.productdetail.performance")
    
    func startTracking(operationId: String) {
        queue.async { [weak self] in
            self?.metrics[operationId] = Date()
        }
    }
    
    func stopTracking(operationId: String) {
        queue.async { [weak self] in
            guard let startTime = self?.metrics.removeValue(forKey: operationId) else { return }
            let duration = Date().timeIntervalSince(startTime)
            
            Logger.performance("Product Detail Operation",
                            duration: duration,
                            threshold: 1.0,
                            metadata: ["operationId": operationId])
        }
    }
}