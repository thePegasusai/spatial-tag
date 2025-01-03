import UIKit
import Combine
import OSLog

/// Root coordinator responsible for managing the application's navigation flow and coordinating
/// between authentication and main feature flows with enhanced security and state management.
final class AppCoordinator: NSObject {
    
    // MARK: - Properties
    
    private let window: UIWindow
    private let navigationController: UINavigationController
    private var childCoordinators: [Coordinator] = []
    private let stateManager: StateRestorationManager
    private let deepLinkHandler: DeepLinkHandler
    private let performanceMonitor: PerformanceMonitor
    private let logger = Logger(subsystem: "com.spatialtag.app", category: "AppCoordinator")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(window: UIWindow) {
        self.window = window
        self.navigationController = UINavigationController()
        self.stateManager = StateRestorationManager()
        self.deepLinkHandler = DeepLinkHandler()
        self.performanceMonitor = PerformanceMonitor()
        
        super.init()
        
        configureWindow()
        setupSecurityMonitoring()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    func start() {
        logger.debug("Starting application flow")
        performanceMonitor.startTracking(identifier: "app_launch")
        
        // Check authentication state
        AppContainer.shared.authService.currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                if let user = user {
                    self?.startMainFlow()
                    self?.logger.info("Starting main flow for authenticated user: \(user.id)")
                } else {
                    self?.startAuthFlow()
                    self?.logger.info("Starting authentication flow")
                }
            }
            .store(in: &cancellables)
        
        // Handle deep links if present
        if let deepLink = deepLinkHandler.currentDeepLink {
            handleDeepLink(deepLink)
        }
        
        window.makeKeyAndVisible()
        performanceMonitor.stopTracking(identifier: "app_launch")
    }
    
    // MARK: - Private Methods
    
    private func configureWindow() {
        window.rootViewController = navigationController
        window.tintColor = .accent
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        
        logger.debug("Window and navigation configuration completed")
    }
    
    private func setupSecurityMonitoring() {
        AppContainer.shared.securityValidator.validationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                if case .failure(let error) = result {
                    self?.handleSecurityViolation(error)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupPerformanceMonitoring() {
        performanceMonitor.metricsPublisher
            .sink { [weak self] metrics in
                self?.logger.performance("App Performance",
                                     duration: metrics.processingTime,
                                     threshold: 0.1,
                                     metadata: ["memoryUsage": metrics.memoryUsage])
            }
            .store(in: &cancellables)
    }
    
    private func startAuthFlow() {
        let authCoordinator = AuthCoordinator(
            navigationController: navigationController,
            completionHandler: { [weak self] coordinator in
                self?.handleAuthenticationCompletion(coordinator)
            }
        )
        
        addChildCoordinator(authCoordinator)
        authCoordinator.start()
    }
    
    private func startMainFlow() {
        let mainCoordinator = MainCoordinator(
            navigationController: navigationController,
            parentCoordinator: self,
            mainViewModel: MainViewModel(
                spatialService: AppContainer.shared.spatialService,
                tagService: TagService.shared
            ),
            analyticsTracker: AppContainer.shared.analyticsService
        )
        
        addChildCoordinator(mainCoordinator)
        mainCoordinator.start()
        
        // Restore state if available
        if let savedState = stateManager.retrieveState() {
            mainCoordinator.restoreState(from: savedState)
        }
    }
    
    private func handleAuthenticationCompletion(_ coordinator: AuthCoordinator) {
        removeChildCoordinator(coordinator)
        startMainFlow()
    }
    
    private func handleDeepLink(_ deepLink: DeepLink) {
        logger.debug("Handling deep link: \(deepLink)")
        // Implement deep link handling logic
    }
    
    private func handleSecurityViolation(_ error: Error) {
        logger.error("Security violation detected: \(error.localizedDescription)")
        
        // Clean up state and restart auth flow
        childCoordinators.forEach { coordinator in
            if let authCoordinator = coordinator as? AuthCoordinator {
                authCoordinator.secureCleanup()
            }
        }
        
        childCoordinators.removeAll()
        startAuthFlow()
    }
    
    private func addChildCoordinator(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }
    
    private func removeChildCoordinator(_ coordinator: Coordinator) {
        childCoordinators = childCoordinators.filter { $0 !== coordinator }
    }
}

// MARK: - Coordinator Conformance

extension AppCoordinator: Coordinator {
    var navigationController: UINavigationController {
        return _navigationController
    }
    
    var childCoordinators: [Coordinator] {
        get { _childCoordinators }
        set { _childCoordinators = newValue }
    }
    
    func start() {
        start()
    }
}