// Foundation - iOS 15.0+ - Core functionality and URL handling
import Foundation

// Internal imports for error handling
import APIError

/// Base URL for API endpoints based on environment
private let BASE_URL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "https://api.spatialtag.com"

/// Current API version
private let API_VERSION = "v1"

/// Default request timeout in seconds
private let DEFAULT_TIMEOUT: TimeInterval = 30

/// Default rate limit (requests per period)
private let DEFAULT_RATE_LIMIT: Int = 100

/// Default rate limit period in seconds
private let DEFAULT_RATE_LIMIT_PERIOD: TimeInterval = 60

/// HTTP methods supported by the API
@frozen public enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
}

/// Cache policies for API requests
@frozen public enum CachePolicy {
    /// No caching
    case noCache
    /// Use cached data if available
    case useCache
    /// Force cache refresh
    case refreshCache
    /// Time-based cache with specific duration
    case timeBasedCache(duration: TimeInterval)
    /// Force refresh regardless of cache state
    case forcedRefresh
    /// Background refresh while serving cached data
    case backgroundRefresh
}

/// Retry policies for failed requests
@frozen public enum RetryPolicy {
    /// No retry attempts
    case none
    /// Immediate retry
    case immediate
    /// Exponential backoff with max attempts
    case exponentialBackoff(maxAttempts: Int)
    /// Custom retry delays
    case custom(delays: [TimeInterval])
}

/// API endpoints with their configurations
@frozen public enum APIEndpoint {
    // MARK: - Authentication Endpoints
    case auth(AuthEndpoint)
    case spatial(SpatialEndpoint)
    case tags(TagEndpoint)
    case users(UserEndpoint)
    case commerce(CommerceEndpoint)
    case realtime(RealtimeEndpoint)
    
    // MARK: - Nested Endpoint Enums
    public enum AuthEndpoint {
        case login
        case signup
        case refresh
        case biometric
    }
    
    public enum SpatialEndpoint {
        case update
        case nearby
        case batch
        case mesh
    }
    
    public enum TagEndpoint {
        case create
        case nearby
        case interact(id: String)
        case delete(id: String)
        case batch
        case search
    }
    
    public enum UserEndpoint {
        case profile
        case update
        case discover
        case status
        case preferences
    }
    
    public enum CommerceEndpoint {
        case wishlist
        case addToWishlist
        case removeFromWishlist(id: String)
        case share
        case collaborate
    }
    
    public enum RealtimeEndpoint {
        case connect
        case status
        case subscribe
    }
    
    // MARK: - Endpoint Properties
    
    /// The endpoint path
    public var path: String {
        switch self {
        case .auth(let endpoint):
            switch endpoint {
            case .login: return "/auth/login"
            case .signup: return "/auth/signup"
            case .refresh: return "/auth/refresh"
            case .biometric: return "/auth/biometric"
            }
            
        case .spatial(let endpoint):
            switch endpoint {
            case .update: return "/spatial/update"
            case .nearby: return "/spatial/nearby"
            case .batch: return "/spatial/batch"
            case .mesh: return "/spatial/mesh"
            }
            
        case .tags(let endpoint):
            switch endpoint {
            case .create: return "/tags"
            case .nearby: return "/tags/nearby"
            case .interact(let id): return "/tags/\(id)/interact"
            case .delete(let id): return "/tags/\(id)"
            case .batch: return "/tags/batch"
            case .search: return "/tags/search"
            }
            
        case .users(let endpoint):
            switch endpoint {
            case .profile: return "/users/profile"
            case .update: return "/users/profile"
            case .discover: return "/users/discover"
            case .status: return "/users/status"
            case .preferences: return "/users/preferences"
            }
            
        case .commerce(let endpoint):
            switch endpoint {
            case .wishlist: return "/wishlist"
            case .addToWishlist: return "/wishlist"
            case .removeFromWishlist(let id): return "/wishlist/\(id)"
            case .share: return "/wishlist/share"
            case .collaborate: return "/wishlist/collaborate"
            }
            
        case .realtime(let endpoint):
            switch endpoint {
            case .connect: return "/ws/connect"
            case .status: return "/ws/status"
            case .subscribe: return "/ws/subscribe"
            }
        }
    }
    
    /// The HTTP method for the endpoint
    public var method: HTTPMethod {
        switch self {
        case .auth(let endpoint):
            switch endpoint {
            case .login, .signup, .refresh, .biometric: return .POST
            }
            
        case .spatial(let endpoint):
            switch endpoint {
            case .update, .batch: return .POST
            case .nearby, .mesh: return .GET
            }
            
        case .tags(let endpoint):
            switch endpoint {
            case .create, .batch, .interact: return .POST
            case .nearby, .search: return .GET
            case .delete: return .DELETE
            }
            
        case .users(let endpoint):
            switch endpoint {
            case .profile, .discover, .status: return .GET
            case .update: return .PUT
            case .preferences: return .PATCH
            }
            
        case .commerce(let endpoint):
            switch endpoint {
            case .wishlist: return .GET
            case .addToWishlist, .share, .collaborate: return .POST
            case .removeFromWishlist: return .DELETE
            }
            
        case .realtime(let endpoint):
            switch endpoint {
            case .connect, .status: return .GET
            case .subscribe: return .POST
            }
        }
    }
    
    /// Whether the endpoint requires authentication
    public var requiresAuth: Bool {
        switch self {
        case .auth(let endpoint):
            switch endpoint {
            case .login, .signup: return false
            default: return true
            }
        default: return true
        }
    }
    
    /// Cache policy for the endpoint
    public var cachePolicy: CachePolicy {
        switch self {
        case .spatial(let endpoint):
            switch endpoint {
            case .nearby: return .timeBasedCache(duration: 30)
            case .mesh: return .timeBasedCache(duration: 12 * 3600)
            default: return .noCache
            }
            
        case .tags(let endpoint):
            switch endpoint {
            case .nearby: return .timeBasedCache(duration: 300)
            case .search: return .timeBasedCache(duration: 300)
            default: return .noCache
            }
            
        case .users(let endpoint):
            switch endpoint {
            case .profile: return .timeBasedCache(duration: 3600)
            default: return .noCache
            }
            
        case .commerce(let endpoint):
            switch endpoint {
            case .wishlist: return .timeBasedCache(duration: 120)
            default: return .noCache
            }
            
        default: return .noCache
        }
    }
    
    /// Rate limit for the endpoint (requests per period)
    public var rateLimit: Int {
        switch self {
        case .spatial:
            return 200
        case .tags:
            return 50
        case .users:
            return 100
        case .commerce:
            return 50
        case .realtime:
            return 20
        default:
            return DEFAULT_RATE_LIMIT
        }
    }
    
    /// Request timeout for the endpoint
    public var timeout: TimeInterval {
        switch self {
        case .spatial(let endpoint):
            switch endpoint {
            case .batch, .mesh: return 60
            default: return DEFAULT_TIMEOUT
            }
        case .tags(.batch):
            return 45
        default:
            return DEFAULT_TIMEOUT
        }
    }
    
    /// Retry policy for the endpoint
    public var retryPolicy: RetryPolicy {
        switch self {
        case .spatial:
            return .exponentialBackoff(maxAttempts: 3)
        case .realtime:
            return .custom(delays: [1, 2, 5])
        case .auth:
            return .immediate
        default:
            return .none
        }
    }
    
    /// Rate limit period for the endpoint in seconds
    public var rateLimitPeriod: TimeInterval {
        return DEFAULT_RATE_LIMIT_PERIOD
    }
}

// MARK: - URL Construction

/// Constructs the full URL for an endpoint
/// - Parameters:
///   - endpoint: The API endpoint
///   - pathParams: Optional path parameters to include
/// - Returns: Constructed URL or nil if invalid
public func buildURL(endpoint: APIEndpoint, pathParams: [String: String]? = nil) -> URL? {
    var urlString = "\(BASE_URL)/\(API_VERSION)\(endpoint.path)"
    
    // Replace path parameters if provided
    if let params = pathParams {
        for (key, value) in params {
            urlString = urlString.replacingOccurrences(of: "{\(key)}", with: value)
        }
    }
    
    return URL(string: urlString)
}