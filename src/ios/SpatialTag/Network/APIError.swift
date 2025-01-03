// Foundation - iOS 15.0+ - Core functionality and error handling
import Foundation

// Internal imports for logging capabilities
import Logger

/// A comprehensive enumeration of all possible API errors with enhanced security and performance considerations
@frozen public enum APIError: LocalizedError {
    // MARK: - Error Cases
    
    /// Invalid URL format or construction
    case invalidURL(String)
    
    /// Network connectivity or request transmission issues
    case networkError(Error)
    
    /// Invalid or unexpected server response format
    case invalidResponse(Int)
    
    /// Data decoding or parsing failure
    case decodingError(Error)
    
    /// Authentication required or token expired (401)
    case unauthorized
    
    /// Access forbidden due to insufficient permissions (403)
    case forbidden
    
    /// Requested resource not found (404)
    case notFound
    
    /// Rate limit exceeded for API requests (429)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    
    /// Internal server error (500)
    case serverError
    
    /// Service temporarily unavailable (503)
    case serviceUnavailable
    
    // MARK: - Properties
    
    /// Human-readable error description
    public var errorDescription: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL format: \(url)"
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
        case .invalidResponse(let statusCode):
            return "Invalid server response with status code: \(statusCode)"
        case .decodingError(let error):
            return "Data decoding failed: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required or token expired"
        case .forbidden:
            return "Access forbidden - insufficient permissions"
        case .notFound:
            return "Requested resource not found"
        case .rateLimitExceeded(let retryAfter):
            if let retry = retryAfter {
                return "Rate limit exceeded. Please retry after \(Int(retry)) seconds"
            }
            return "Rate limit exceeded"
        case .serverError:
            return "Internal server error occurred"
        case .serviceUnavailable:
            return "Service temporarily unavailable"
        }
    }
    
    /// HTTP status code associated with the error
    public var statusCode: Int {
        switch self {
        case .unauthorized:
            return 401
        case .forbidden:
            return 403
        case .notFound:
            return 404
        case .rateLimitExceeded:
            return 429
        case .serverError:
            return 500
        case .serviceUnavailable:
            return 503
        case .invalidResponse(let code):
            return code
        default:
            return 0
        }
    }
    
    /// Error domain for categorization and tracking
    public var errorDomain: String {
        return "com.spatialtag.api"
    }
    
    /// Indicates if the error can be retried
    public var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .serviceUnavailable, .rateLimitExceeded:
            return true
        default:
            return false
        }
    }
    
    /// Optional recovery message for user feedback
    public var recoveryMessage: String? {
        switch self {
        case .unauthorized:
            return "Please sign in again to continue"
        case .forbidden:
            return "You don't have permission to perform this action"
        case .rateLimitExceeded(let retryAfter):
            if let retry = retryAfter {
                return "Please try again after \(Int(retry)) seconds"
            }
            return "Please try again later"
        case .networkError:
            return "Please check your internet connection and try again"
        case .serviceUnavailable:
            return "The service is temporarily unavailable. Please try again later"
        default:
            return nil
        }
    }
    
    // MARK: - Methods
    
    /// Asynchronously logs the error with appropriate context while maintaining performance
    /// - Parameters:
    ///   - context: Additional context about where/when the error occurred
    ///   - metadata: Optional metadata for detailed error tracking
    public func log(context: String? = nil, metadata: [String: Any]? = nil) {
        var errorMetadata: [String: Any] = [
            "statusCode": statusCode,
            "domain": errorDomain,
            "retryable": isRetryable
        ]
        
        if let context = context {
            errorMetadata["context"] = context
        }
        
        if let metadata = metadata {
            errorMetadata.merge(metadata) { current, _ in current }
        }
        
        // Asynchronously log the error to maintain performance
        Logger.logAsync(level: .error,
                       message: errorDescription,
                       category: "API",
                       metadata: errorMetadata)
    }
    
    /// Determines if the error can be automatically recovered from
    /// - Returns: Boolean indicating if automatic recovery is possible
    public func isRecoverable() -> Bool {
        switch self {
        case .unauthorized:
            // Can potentially refresh token
            return true
        case .rateLimitExceeded(let retryAfter):
            // Can retry after specified delay
            return retryAfter != nil
        case .networkError, .serviceUnavailable:
            // Can retry with exponential backoff
            return true
        default:
            return false
        }
    }
}