// Foundation - iOS 15.0+ - Core networking functionality
import Foundation
// Combine - iOS 15.0+ - Asynchronous request handling
import Combine

// Internal imports
import APIError
import APIEndpoint
import NetworkMonitor

/// Core API client providing secure and performant network communication
@available(iOS 15.0, *)
public final class APIClient {
    // MARK: - Constants
    
    private let DEFAULT_HEADERS: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Client-Version": "1.0.0",
        "X-Platform": "iOS"
    ]
    
    private let REQUEST_TIMEOUT: TimeInterval = 30.0
    private let MAX_RETRY_ATTEMPTS: Int = 3
    private let CACHE_SIZE_MEMORY: Int = 20_971_520  // 20MB
    private let CACHE_SIZE_DISK: Int = 104_857_600   // 100MB
    private let RATE_LIMIT_REQUESTS: Int = 100
    private let RATE_LIMIT_WINDOW: TimeInterval = 60.0
    
    // MARK: - Properties
    
    public static let shared = APIClient()
    
    private var session: URLSession
    private var authToken: String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let cache: URLCache
    private let rateLimiter: RateLimiter
    private let requestQueue: RequestQueue
    private let performanceMonitor: PerformanceMonitor
    private let securityManager: SecurityManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Configure URLCache
        self.cache = URLCache(memoryCapacity: CACHE_SIZE_MEMORY,
                            diskCapacity: CACHE_SIZE_DISK,
                            diskPath: "com.spatialtag.apiclient")
        
        // Configure session configuration with security settings
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = REQUEST_TIMEOUT
        configuration.timeoutIntervalForResource = REQUEST_TIMEOUT * 2
        
        // Initialize security manager and configure certificate pinning
        self.securityManager = SecurityManager()
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.httpAdditionalHeaders = DEFAULT_HEADERS
        
        // Initialize session with security delegate
        self.session = URLSession(configuration: configuration,
                                delegate: securityManager,
                                delegateQueue: nil)
        
        // Initialize JSON coding
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        
        // Initialize request management
        self.rateLimiter = RateLimiter(limit: RATE_LIMIT_REQUESTS,
                                      window: RATE_LIMIT_WINDOW)
        self.requestQueue = RequestQueue()
        self.performanceMonitor = PerformanceMonitor()
        
        // Setup network monitoring
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Makes a secure API request with caching and monitoring
    /// - Parameters:
    ///   - endpoint: The API endpoint to request
    ///   - body: Optional request body
    ///   - headers: Optional additional headers
    /// - Returns: Publisher emitting decoded response or error
    public func request<T: Decodable>(endpoint: APIEndpoint,
                                    body: Encodable? = nil,
                                    headers: [String: String]? = nil) -> AnyPublisher<T, APIError> {
        // Check network connectivity
        guard NetworkMonitor.shared.isConnected else {
            return Fail(error: APIError.networkError(NSError(domain: "", code: -1)))
                .eraseToAnyPublisher()
        }
        
        // Check rate limits
        guard rateLimiter.shouldAllowRequest() else {
            return Fail(error: APIError.rateLimitExceeded(retryAfter: rateLimiter.timeUntilReset))
                .eraseToAnyPublisher()
        }
        
        // Build URL request
        guard let url = buildURL(endpoint: endpoint) else {
            return Fail(error: APIError.invalidURL(endpoint.path))
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeout
        
        // Add authentication if required
        if endpoint.requiresAuth {
            guard let token = authToken else {
                return Fail(error: APIError.unauthorized)
                    .eraseToAnyPublisher()
            }
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add custom headers
        headers?.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        
        // Add request body
        if let body = body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                return Fail(error: APIError.decodingError(error))
                    .eraseToAnyPublisher()
            }
        }
        
        // Check cache based on policy
        if let cachedResponse = checkCache(for: request, policy: endpoint.cachePolicy) {
            return Just(cachedResponse)
                .decode(type: T.self, decoder: decoder)
                .mapError { APIError.decodingError($0) }
                .eraseToAnyPublisher()
        }
        
        // Start performance monitoring
        let requestId = UUID().uuidString
        performanceMonitor.startTracking(requestId: requestId)
        
        // Queue and execute request
        return requestQueue.enqueue(request: request)
            .flatMap { [weak self] request -> AnyPublisher<Data, APIError> in
                guard let self = self else {
                    return Fail(error: APIError.networkError(NSError(domain: "", code: -1)))
                        .eraseToAnyPublisher()
                }
                
                return self.executeRequest(request,
                                        endpoint: endpoint,
                                        requestId: requestId)
            }
            .decode(type: T.self, decoder: decoder)
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                return APIError.decodingError(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// Updates the authentication token
    /// - Parameter token: The new token or nil to clear
    public func setAuthToken(_ token: String?) {
        self.authToken = token
        if token == nil {
            cache.removeAllCachedResponses()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        NetworkMonitor.shared.networkStatus
            .sink { [weak self] status in
                if case .disconnected = status {
                    self?.cache.removeAllCachedResponses()
                }
            }
            .store(in: &cancellables)
    }
    
    private func executeRequest(_ request: URLRequest,
                              endpoint: APIEndpoint,
                              requestId: String) -> AnyPublisher<Data, APIError> {
        return session.dataTaskPublisher(for: request)
            .tryMap { [weak self] data, response -> Data in
                guard let self = self else { throw APIError.networkError(NSError(domain: "", code: -1)) }
                
                // Stop performance tracking
                self.performanceMonitor.stopTracking(requestId: requestId)
                
                // Validate response
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse(-1)
                }
                
                // Handle response based on status code
                switch httpResponse.statusCode {
                case 200...299:
                    // Cache successful response
                    self.cacheResponse(data: data,
                                    response: httpResponse,
                                    for: request,
                                    policy: endpoint.cachePolicy)
                    return data
                case 401:
                    throw APIError.unauthorized
                case 403:
                    throw APIError.forbidden
                case 404:
                    throw APIError.notFound
                case 429:
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap { TimeInterval($0) }
                    throw APIError.rateLimitExceeded(retryAfter: retryAfter)
                case 500:
                    throw APIError.serverError
                case 503:
                    throw APIError.serviceUnavailable
                default:
                    throw APIError.invalidResponse(httpResponse.statusCode)
                }
            }
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                return APIError.networkError(error)
            }
            .retry(endpoint.retryPolicy)
            .eraseToAnyPublisher()
    }
    
    private func checkCache(for request: URLRequest,
                          policy: CachePolicy) -> Data? {
        switch policy {
        case .noCache, .forcedRefresh:
            return nil
        case .useCache:
            return cache.cachedResponse(for: request)?.data
        case .timeBasedCache(let duration):
            guard let cachedResponse = cache.cachedResponse(for: request),
                  let timestamp = cachedResponse.userInfo?["timestamp"] as? Date,
                  Date().timeIntervalSince(timestamp) < duration else {
                return nil
            }
            return cachedResponse.data
        case .backgroundRefresh:
            return cache.cachedResponse(for: request)?.data
        }
    }
    
    private func cacheResponse(data: Data,
                             response: HTTPURLResponse,
                             for request: URLRequest,
                             policy: CachePolicy) {
        guard policy != .noCache else { return }
        
        let cachedResponse = CachedURLResponse(
            response: response,
            data: data,
            userInfo: ["timestamp": Date()],
            storagePolicy: .allowed
        )
        
        cache.storeCachedResponse(cachedResponse, for: request)
    }
}

// MARK: - Helper Classes

private final class SecurityManager: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Implement certificate pinning
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}

private final class RateLimiter {
    private let limit: Int
    private let window: TimeInterval
    private var requestCount = 0
    private var windowStart: Date
    
    init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
        self.windowStart = Date()
    }
    
    var timeUntilReset: TimeInterval {
        let elapsed = Date().timeIntervalSince(windowStart)
        return max(0, window - elapsed)
    }
    
    func shouldAllowRequest() -> Bool {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= window {
            windowStart = now
            requestCount = 0
        }
        
        guard requestCount < limit else { return false }
        requestCount += 1
        return true
    }
}

private final class RequestQueue {
    private let queue = DispatchQueue(label: "com.spatialtag.requestqueue",
                                    qos: .userInitiated,
                                    attributes: .concurrent)
    private let semaphore = DispatchSemaphore(value: 6)
    
    func enqueue(request: URLRequest) -> AnyPublisher<URLRequest, APIError> {
        return Future { [weak self] promise in
            self?.queue.async {
                self?.semaphore.wait()
                promise(.success(request))
                self?.semaphore.signal()
            }
        }
        .eraseToAnyPublisher()
    }
}

private final class PerformanceMonitor {
    private var metrics: [String: Date] = [:]
    private let queue = DispatchQueue(label: "com.spatialtag.performancemonitor")
    
    func startTracking(requestId: String) {
        queue.async { [weak self] in
            self?.metrics[requestId] = Date()
        }
    }
    
    func stopTracking(requestId: String) {
        queue.async { [weak self] in
            guard let startTime = self?.metrics.removeValue(forKey: requestId) else { return }
            let duration = Date().timeIntervalSince(startTime)
            
            Logger.performance("API Request",
                             duration: duration,
                             threshold: 1.0,
                             metadata: ["requestId": requestId])
        }
    }
}