// Foundation - iOS 15.0+ - Core functionality
import Foundation
// Combine - iOS 15.0+ - Async request handling
import Combine
// ARKit - iOS 15.0+ - LiDAR and spatial awareness
import ARKit

// MARK: - Constants

private let DEFAULT_RADIUS: Double = 50.0
private let TAG_CACHE_DURATION: Double = 300.0 // 5 minutes
private let LIDAR_PRECISION_THRESHOLD: Double = 0.01 // 1cm precision
private let MAX_CACHE_SIZE: Int = 1000
private let PERFORMANCE_THRESHOLD_MS: Double = 100.0

// MARK: - Cache Types

private class CachedTags {
    let tags: [Tag]
    let timestamp: Date
    
    init(tags: [Tag], timestamp: Date = Date()) {
        self.tags = tags
        self.timestamp = timestamp
    }
    
    var isValid: Bool {
        return Date().timeIntervalSince(timestamp) < TAG_CACHE_DURATION
    }
}

// MARK: - TagService

@available(iOS 15.0, *)
public final class TagService {
    
    // MARK: - Properties
    
    public static let shared = TagService()
    
    private let apiClient: APIClient
    private let tagsSubject = CurrentValueSubject<[Tag], Never>([])
    private let tagCache = NSCache<NSString, CachedTags>()
    private let cacheLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    private init() {
        self.apiClient = APIClient.shared
        configureCache()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Creates a new spatial tag with LiDAR precision validation
    /// - Parameters:
    ///   - location: The spatial location for the tag
    ///   - content: Tag content
    ///   - visibilityRadius: Optional visibility radius (defaults to 50m)
    ///   - expirationHours: Optional expiration time in hours (defaults to 24h)
    /// - Returns: Publisher emitting created tag or error
    public func createTag(location: Location,
                         content: String,
                         visibilityRadius: Double? = nil,
                         expirationHours: TimeInterval? = nil) -> AnyPublisher<Tag, Error> {
        
        let startTime = DispatchTime.now()
        
        // Validate LiDAR precision
        guard let spatialCoordinate = location.spatialCoordinate,
              Double(simd_length(spatialCoordinate)) >= LIDAR_PRECISION_THRESHOLD else {
            return Fail(error: LocationError.precisionNotMet).eraseToAnyPublisher()
        }
        
        // Prepare request payload
        let payload = [
            "location": location,
            "content": content,
            "visibilityRadius": visibilityRadius ?? DEFAULT_RADIUS,
            "expirationHours": expirationHours ?? 24.0
        ] as [String: Any]
        
        return apiClient.request(endpoint: .tags(.create), body: payload)
            .handleEvents(receiveOutput: { [weak self] tag in
                self?.handleNewTag(tag)
                
                // Log performance metrics
                let endTime = DispatchTime.now()
                let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                
                self?.logger.performance("Tag Creation",
                                      duration: elapsed,
                                      threshold: PERFORMANCE_THRESHOLD_MS,
                                      metadata: ["tagId": tag.id.uuidString])
            })
            .eraseToAnyPublisher()
    }
    
    /// Retrieves tags within specified radius with caching
    /// - Parameters:
    ///   - location: Center location for search
    ///   - radius: Search radius in meters
    /// - Returns: Publisher emitting array of nearby tags
    public func getNearbyTags(location: Location,
                            radius: Double = DEFAULT_RADIUS) -> AnyPublisher<[Tag], Error> {
        
        let startTime = DispatchTime.now()
        
        // Check cache first
        if let cachedResult = checkCache(for: location, radius: radius) {
            return Just(cachedResult)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Prepare request parameters
        let params = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "radius": radius
        ] as [String: Any]
        
        return apiClient.request(endpoint: .tags(.nearby), body: params)
            .map { (tags: [Tag]) -> [Tag] in
                // Filter expired tags
                return tags.filter { !$0.isExpired() }
            }
            .handleEvents(receiveOutput: { [weak self] tags in
                // Update cache and subject
                self?.updateCache(tags: tags, for: location, radius: radius)
                self?.tagsSubject.send(tags)
                
                // Log performance metrics
                let endTime = DispatchTime.now()
                let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
                
                self?.logger.performance("Nearby Tags Retrieval",
                                      duration: elapsed,
                                      threshold: PERFORMANCE_THRESHOLD_MS,
                                      metadata: ["tagCount": tags.count])
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func configureCache() {
        tagCache.countLimit = MAX_CACHE_SIZE
        
        // Setup periodic cache cleanup
        Timer.publish(every: TAG_CACHE_DURATION / 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cleanCache()
            }
            .store(in: &cancellables)
    }
    
    private func setupPerformanceMonitoring() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func checkCache(for location: Location, radius: Double) -> [Tag]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let cacheKey = "\(location.coordinate.latitude),\(location.coordinate.longitude),\(radius)" as NSString
        guard let cached = tagCache.object(forKey: cacheKey), cached.isValid else {
            return nil
        }
        
        return cached.tags
    }
    
    private func updateCache(tags: [Tag], for location: Location, radius: Double) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let cacheKey = "\(location.coordinate.latitude),\(location.coordinate.longitude),\(radius)" as NSString
        let cachedTags = CachedTags(tags: tags)
        tagCache.setObject(cachedTags, forKey: cacheKey)
    }
    
    private func cleanCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        tagCache.removeAllObjects()
        logger.debug("Tag cache cleaned")
    }
    
    private func handleNewTag(_ tag: Tag) {
        var currentTags = tagsSubject.value
        currentTags.append(tag)
        tagsSubject.send(currentTags)
    }
    
    private func handleMemoryWarning() {
        cleanCache()
        logger.warning("Memory warning received - cache cleared")
    }
}