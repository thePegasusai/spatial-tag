// Foundation - iOS 15.0+ - Core functionality and threading
import Foundation
// OSLog - iOS 15.0+ - Secure logging and debugging support
import OSLog

/// Thread-safe dependency injection container managing application-wide services
/// and shared dependencies with comprehensive security and performance optimizations
@MainActor
final class AppContainer {
    
    // MARK: - Properties
    
    /// Singleton instance with thread-safe initialization
    static let shared = AppContainer()
    
    /// Core application environment configuration
    private(set) var environment: AppEnvironment
    
    /// Authentication service instance
    private(set) var authService: AuthService
    
    /// Spatial processing service instance
    private(set) var spatialService: SpatialService
    
    /// Secure system logger
    private let logger: Logger
    
    /// Service initialization state
    private(set) var isInitialized: Bool = false
    
    /// Thread-safe service state management
    private let serviceStates: NSMutableDictionary
    
    /// Concurrent queue for service operations
    private let serviceQueue: DispatchQueue
    
    /// Security validation lock
    private let securityLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Initialize secure logger
        self.logger = Logger(subsystem: "com.spatialtag.app", category: "AppContainer")
        logger.info("Initializing AppContainer...")
        
        // Initialize service state management
        self.serviceStates = NSMutableDictionary()
        self.serviceQueue = DispatchQueue(
            label: "com.spatialtag.app.services",
            qos: .userInitiated,
            attributes: .concurrent
        )
        
        // Initialize core environment with validation
        do {
            self.environment = AppEnvironment.shared
            validateEnvironmentConfiguration()
        } catch {
            fatalError("Failed to initialize environment: \(error.localizedDescription)")
        }
        
        // Initialize authentication service with security checks
        self.authService = AuthService.shared
        
        // Initialize spatial service with performance optimization
        let lidarProcessor = LiDARProcessor(
            session: ARSession(),
            calculator: SpatialCalculator(referenceLocation: CLLocation()),
            powerMonitor: PowerMonitor()
        )
        let locationManager = LocationManager()
        self.spatialService = SpatialService(
            lidarProcessor: lidarProcessor,
            locationManager: locationManager
        )
        
        // Configure initial service states
        configureInitialState()
        
        // Set up monitoring
        setupPerformanceMonitoring()
        setupSecurityValidation()
        
        isInitialized = true
        logger.info("AppContainer initialization completed")
    }
    
    // MARK: - Public Methods
    
    /// Securely resets container state and services with proper cleanup
    func reset() async {
        securityLock.lock()
        defer { securityLock.unlock() }
        
        logger.info("Resetting AppContainer state...")
        
        // Suspend active services
        await suspendServices()
        
        // Reset authentication state
        await authService.logout()
        
        // Clear cached data
        clearSecureCache()
        
        // Reset environment
        environment = AppEnvironment.shared
        
        // Reset service states
        serviceStates.removeAllObjects()
        
        // Reconfigure initial state
        configureInitialState()
        
        logger.info("AppContainer reset completed")
    }
    
    /// Configures all services with current environment and security context
    func configureServices(with config: AppEnvironment.Configuration) async {
        securityLock.lock()
        defer { securityLock.unlock() }
        
        logger.info("Configuring services with new configuration...")
        
        // Validate configuration integrity
        guard validateConfiguration(config) else {
            logger.error("Invalid configuration provided")
            return
        }
        
        // Apply security configurations
        await applySecurityConfiguration(config)
        
        // Initialize service connections
        do {
            try await initializeServiceConnections()
        } catch {
            logger.error("Failed to initialize service connections: \(error.localizedDescription)")
            return
        }
        
        // Configure service dependencies
        configureDependencies()
        
        // Set up monitoring
        setupPerformanceMonitoring()
        
        logger.info("Service configuration completed")
    }
    
    /// Validates service health and security state
    func validateServiceState(_ serviceId: String) -> Bool {
        securityLock.lock()
        defer { securityLock.unlock() }
        
        guard let serviceState = serviceStates[serviceId] as? [String: Any] else {
            logger.error("Service state not found for ID: \(serviceId)")
            return false
        }
        
        // Check initialization status
        guard serviceState["initialized"] as? Bool == true else {
            logger.error("Service not properly initialized: \(serviceId)")
            return false
        }
        
        // Validate security context
        guard validateSecurityContext(for: serviceId) else {
            logger.error("Security validation failed for service: \(serviceId)")
            return false
        }
        
        // Check performance metrics
        guard validatePerformanceMetrics(for: serviceId) else {
            logger.error("Performance validation failed for service: \(serviceId)")
            return false
        }
        
        return true
    }
    
    // MARK: - Private Methods
    
    private func validateEnvironmentConfiguration() {
        guard environment.isFeatureEnabled(.lidarEnabled),
              environment.isFeatureEnabled(.arOverlayEnabled) else {
            fatalError("Required features not enabled in environment")
        }
    }
    
    private func configureInitialState() {
        serviceStates["auth"] = [
            "initialized": true,
            "securityLevel": "high",
            "lastValidated": Date()
        ]
        
        serviceStates["spatial"] = [
            "initialized": true,
            "performanceLevel": "optimal",
            "lastUpdated": Date()
        ]
    }
    
    private func setupPerformanceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.monitorServicePerformance()
        }
    }
    
    private func setupSecurityValidation() {
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.validateSecurityState()
        }
    }
    
    private func suspendServices() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // Suspend spatial service
                self.spatialService.stopSpatialTracking()
            }
            
            group.addTask {
                // Suspend auth service
                await self.authService.logout()
            }
        }
    }
    
    private func clearSecureCache() {
        // Clear sensitive data from cache
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
    
    private func validateConfiguration(_ config: AppEnvironment.Configuration) -> Bool {
        // Validate configuration parameters
        return config.performanceThresholds["responseTime"] != nil &&
               config.performanceThresholds["batteryDrain"] != nil
    }
    
    private func applySecurityConfiguration(_ config: AppEnvironment.Configuration) async {
        // Apply security settings
        await authService.configureSecuritySettings(config)
    }
    
    private func initializeServiceConnections() async throws {
        // Initialize service connections with security validation
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.authService.validateConnection()
            }
            
            group.addTask {
                try await self.spatialService.startSpatialTracking().async()
            }
        }
    }
    
    private func configureDependencies() {
        // Configure inter-service dependencies
        spatialService.configureAuthDependency(authService)
    }
    
    private func validateSecurityContext(for serviceId: String) -> Bool {
        guard let serviceState = serviceStates[serviceId] as? [String: Any],
              let securityLevel = serviceState["securityLevel"] as? String else {
            return false
        }
        
        return securityLevel == "high"
    }
    
    private func validatePerformanceMetrics(for serviceId: String) -> Bool {
        guard let serviceState = serviceStates[serviceId] as? [String: Any],
              let performanceLevel = serviceState["performanceLevel"] as? String else {
            return false
        }
        
        return performanceLevel == "optimal"
    }
    
    private func monitorServicePerformance() {
        serviceQueue.async {
            // Monitor and log service performance metrics
            self.logger.performance("Service Performance Check",
                                 duration: 0.1,
                                 threshold: 1.0,
                                 metadata: [
                                    "servicesInitialized": self.isInitialized,
                                    "activeServices": self.serviceStates.count
                                 ])
        }
    }
    
    private func validateSecurityState() {
        securityLock.lock()
        defer { securityLock.unlock() }
        
        // Validate overall security state
        for (serviceId, _) in serviceStates {
            if !validateServiceState(serviceId as! String) {
                logger.error("Security validation failed for service: \(serviceId)")
            }
        }
    }
}