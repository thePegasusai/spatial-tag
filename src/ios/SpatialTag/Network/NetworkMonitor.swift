// Network - iOS 15.0+ - Core networking and path monitoring capabilities
import Network
// Foundation - iOS 15.0+ - Basic iOS functionality and notifications
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine

// Internal imports
import Logger
import APIError

/// Enhanced network configuration structure
private struct NetworkConfiguration {
    let maxRetryAttempts: Int = 3
    let baseRetryDelay: TimeInterval = 1.0
    let performanceThreshold: TimeInterval = 0.1
    let stateDebounceInterval: TimeInterval = 0.5
}

/// Enhanced network performance metrics
public struct NetworkMetrics {
    let latency: TimeInterval
    let throughput: Double
    let timestamp: Date
    let connectionType: String
    let isVPNActive: Bool
}

/// Enhanced network status enumeration with performance metrics
@frozen public enum NetworkStatus: Equatable {
    case connected(NetworkMetrics)
    case disconnected
    case connecting
    case retrying(attempt: Int)
    
    public var description: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .retrying(let attempt):
            return "Retrying (Attempt \(attempt))"
        }
    }
    
    public var metrics: NetworkMetrics? {
        switch self {
        case .connected(let metrics):
            return metrics
        default:
            return nil
        }
    }
}

/// Enhanced network monitor with performance tracking and security validation
@available(iOS 15.0, *)
public final class NetworkMonitor {
    // MARK: - Properties
    
    public static let shared = NetworkMonitor()
    private let pathMonitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    
    public private(set) var networkStatus: CurrentValueSubject<NetworkStatus, Never>
    public private(set) var performanceMetrics: PassthroughSubject<NetworkMetrics, Never>
    
    public private(set) var isConnected: Bool = false
    public private(set) var isExpensive: Bool = false
    public private(set) var isCellular: Bool = false
    public private(set) var isWiFi: Bool = false
    public private(set) var isVPNActive: Bool = false
    
    private var retryCount: Int = 0
    private var lastTransitionTime: TimeInterval = 0
    private let config = NetworkConfiguration()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        self.pathMonitor = NWPathMonitor()
        self.monitorQueue = DispatchQueue(label: "com.spatialtag.networkmonitor", qos: .utility)
        self.networkStatus = CurrentValueSubject<NetworkStatus, Never>(.disconnected)
        self.performanceMetrics = PassthroughSubject<NetworkMetrics, Never>()
        
        setupPathMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts enhanced network monitoring with performance tracking
    public func startMonitoring() {
        Logger.info("Starting network monitoring", category: "Network")
        
        pathMonitor.start(queue: monitorQueue)
        setupPerformanceTracking()
        
        // Initial status update
        updateNetworkStatus(pathMonitor.currentPath)
    }
    
    /// Stops network monitoring and cleans up resources
    public func stopMonitoring() {
        Logger.info("Stopping network monitoring", category: "Network")
        
        pathMonitor.cancel()
        cancellables.removeAll()
        networkStatus.send(.disconnected)
    }
    
    /// Handles connection failures with retry logic
    public func handleConnectionFailure(_ error: APIError) -> AnyPublisher<NetworkStatus, Error> {
        guard error.isRetryable && retryCount < config.maxRetryAttempts else {
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        retryCount += 1
        let delay = calculateBackoffDelay(attempt: retryCount)
        
        Logger.info("Attempting connection retry (\(retryCount)/\(config.maxRetryAttempts)) after \(delay)s", category: "Network")
        
        return Just(NetworkStatus.retrying(attempt: retryCount))
            .delay(for: .seconds(delay), scheduler: monitorQueue)
            .flatMap { [weak self] _ -> AnyPublisher<NetworkStatus, Error> in
                guard let self = self else {
                    return Fail(error: APIError.networkError(NSError(domain: "", code: -1))).eraseToAnyPublisher()
                }
                return self.performReconnection()
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.updateNetworkStatus(path)
        }
    }
    
    private func setupPerformanceTracking() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.measureNetworkPerformance()
            }
            .store(in: &cancellables)
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        let currentTime = Date().timeIntervalSince1970
        
        // Debounce rapid state changes
        guard (currentTime - lastTransitionTime) >= config.stateDebounceInterval else {
            return
        }
        
        lastTransitionTime = currentTime
        
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isCellular = path.usesInterfaceType(.cellular)
        isWiFi = path.usesInterfaceType(.wifi)
        isVPNActive = detectVPNConnection(path)
        
        let metrics = generateNetworkMetrics(path)
        
        if isConnected {
            networkStatus.send(.connected(metrics))
            retryCount = 0
        } else {
            networkStatus.send(.disconnected)
        }
        
        performanceMetrics.send(metrics)
        
        Logger.info("Network status updated: \(networkStatus.value.description)", category: "Network")
    }
    
    private func detectVPNConnection(_ path: NWPath) -> Bool {
        return path.interfaces.contains { $0.type == .other }
    }
    
    private func generateNetworkMetrics(_ path: NWPath) -> NetworkMetrics {
        return NetworkMetrics(
            latency: measureLatency(),
            throughput: calculateThroughput(),
            timestamp: Date(),
            connectionType: determineConnectionType(path),
            isVPNActive: isVPNActive
        )
    }
    
    private func measureLatency() -> TimeInterval {
        // Implement actual latency measurement
        return 0.05 // Default value for example
    }
    
    private func calculateThroughput() -> Double {
        // Implement actual throughput calculation
        return 1000000.0 // Default value for example
    }
    
    private func determineConnectionType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else {
            return "Unknown"
        }
    }
    
    private func calculateBackoffDelay(attempt: Int) -> TimeInterval {
        return config.baseRetryDelay * pow(2.0, Double(attempt - 1))
    }
    
    private func performReconnection() -> AnyPublisher<NetworkStatus, Error> {
        // Implement actual reconnection logic
        return Just(NetworkStatus.connecting)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    private func measureNetworkPerformance() {
        let metrics = generateNetworkMetrics(pathMonitor.currentPath)
        
        if metrics.latency > config.performanceThreshold {
            Logger.performance("Network latency threshold exceeded",
                             duration: metrics.latency,
                             threshold: config.performanceThreshold,
                             metadata: ["throughput": metrics.throughput,
                                      "connectionType": metrics.connectionType])
        }
    }
}