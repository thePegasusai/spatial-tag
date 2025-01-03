// Foundation - iOS 15.0+ - Core functionality and threading
import Foundation

// MARK: - Global Constants

private let DEFAULT_MAX_TAG_RADIUS = 50
private let DEFAULT_USER_DISCOVERY_RANGE = 100
private let DEFAULT_BATTERY_THRESHOLD = 0.15
private let PERFORMANCE_UPDATE_INTERVAL = 300
private let MAX_CONCURRENT_TAGS = 50
private let SPATIAL_REFRESH_RATE = 30

// MARK: - Environment Enumeration

@objc public enum Environment: Int {
    case development
    case staging
    case production
    
    var apiURL: String {
        switch self {
        case .development:
            return "https://dev-api.spatialtag.com"
        case .staging:
            return "https://staging-api.spatialtag.com"
        case .production:
            return "https://api.spatialtag.com"
        }
    }
    
    var logLevel: LogLevel {
        switch self {
        case .development:
            return .debug
        case .staging:
            return .info
        case .production:
            return .warning
        }
    }
    
    var performanceThresholds: [String: Double] {
        switch self {
        case .development:
            return ["responseTime": 0.5, "batteryDrain": 0.2]
        case .staging:
            return ["responseTime": 0.2, "batteryDrain": 0.17]
        case .production:
            return ["responseTime": 0.1, "batteryDrain": 0.15]
        }
    }
}

// MARK: - Feature Flag Enumeration

@objc public enum FeatureFlag: Int {
    case lidarEnabled
    case arOverlayEnabled
    case commerceEnabled
    case pushNotificationsEnabled
    case spatialMappingEnabled
    case tagPersistenceEnabled
    
    var isEnabledByDefault: Bool {
        switch self {
        case .lidarEnabled, .arOverlayEnabled:
            return true
        case .commerceEnabled, .pushNotificationsEnabled:
            return true
        case .spatialMappingEnabled, .tagPersistenceEnabled:
            return false
        }
    }
}

// MARK: - AppEnvironment Class

@objc @objcMembers public class AppEnvironment {
    // MARK: - Properties
    
    public static let shared = AppEnvironment(environment: .production)
    
    private(set) var current: Environment
    private(set) var apiBaseURL: String
    private(set) var maxTagRadius: Int
    private(set) var maxUserDiscoveryRange: Int
    private(set) var batteryUsageThreshold: Double
    private(set) var enabledFeatures: Set<FeatureFlag>
    private(set) var performanceMetrics: [String: Any]
    
    private let configLock = NSLock()
    
    // MARK: - Initialization
    
    public init(environment: Environment) {
        self.current = environment
        self.apiBaseURL = environment.apiURL
        self.maxTagRadius = DEFAULT_MAX_TAG_RADIUS
        self.maxUserDiscoveryRange = DEFAULT_USER_DISCOVERY_RANGE
        self.batteryUsageThreshold = DEFAULT_BATTERY_THRESHOLD
        self.enabledFeatures = Set<FeatureFlag>()
        self.performanceMetrics = [:]
        
        configureEnvironment()
        configureFeatureFlags()
        configureLogging()
        startPerformanceMonitoring()
    }
    
    // MARK: - Private Configuration Methods
    
    private func configureEnvironment() {
        configLock.lock()
        defer { configLock.unlock() }
        
        maxTagRadius = current == .production ? DEFAULT_MAX_TAG_RADIUS : DEFAULT_MAX_TAG_RADIUS * 2
        maxUserDiscoveryRange = current == .production ? DEFAULT_USER_DISCOVERY_RANGE : DEFAULT_USER_DISCOVERY_RANGE * 2
        batteryUsageThreshold = current.performanceThresholds["batteryDrain"] ?? DEFAULT_BATTERY_THRESHOLD
    }
    
    private func configureFeatureFlags() {
        configLock.lock()
        defer { configLock.unlock() }
        
        enabledFeatures = Set(FeatureFlag.allCases.filter { flag in
            switch current {
            case .development:
                return true
            case .staging:
                return flag.isEnabledByDefault
            case .production:
                return flag.isEnabledByDefault && flag != .spatialMappingEnabled
            }
        })
    }
    
    private func configureLogging() {
        Logger.shared.setLogLevel(current.logLevel)
        Logger.shared.logPerformanceMetric("AppEnvironment initialized",
                                         metadata: ["environment": current,
                                                  "maxTagRadius": maxTagRadius,
                                                  "maxUserDiscoveryRange": maxUserDiscoveryRange])
    }
    
    private func startPerformanceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: TimeInterval(PERFORMANCE_UPDATE_INTERVAL), repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    private func updatePerformanceMetrics() {
        configLock.lock()
        defer { configLock.unlock() }
        
        performanceMetrics = [
            "timestamp": Date().timeIntervalSince1970,
            "batteryLevel": UIDevice.current.batteryLevel,
            "memoryUsage": ProcessInfo.processInfo.physicalMemory,
            "activeTagCount": MAX_CONCURRENT_TAGS,
            "spatialRefreshRate": SPATIAL_REFRESH_RATE
        ]
        
        Logger.shared.logPerformanceMetric("Performance metrics updated",
                                         metadata: performanceMetrics)
    }
    
    // MARK: - Public Methods
    
    public func isFeatureEnabled(_ feature: FeatureFlag) -> Bool {
        configLock.lock()
        defer { configLock.unlock() }
        
        return enabledFeatures.contains(feature)
    }
    
    public func getPerformanceConfig() -> [String: Any] {
        configLock.lock()
        defer { configLock.unlock() }
        
        return [
            "maxTagRadius": maxTagRadius,
            "maxUserDiscoveryRange": maxUserDiscoveryRange,
            "batteryUsageThreshold": batteryUsageThreshold,
            "performanceThresholds": current.performanceThresholds,
            "spatialRefreshRate": SPATIAL_REFRESH_RATE,
            "maxConcurrentTags": MAX_CONCURRENT_TAGS
        ]
    }
}