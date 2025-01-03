import UIKit
import Combine
import os.log

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    // MARK: - Properties
    
    var window: UIWindow?
    private var coordinator: AppCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.spatialtag", category: "SceneDelegate")
    private let performanceMonitor = PerformanceMonitor()
    
    // MARK: - Scene Lifecycle
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UISceneConnectionOptions) {
        let signpostID = OSSignpostID(log: .default)
        os_signpost(.begin, log: .default, name: "SceneConfiguration", signpostID: signpostID)
        
        guard let windowScene = (scene as? UIWindowScene) else {
            logger.error("Failed to cast scene to UIWindowScene")
            return
        }
        
        do {
            // Create and configure window
            let window = UIWindow(windowScene: windowScene)
            self.window = window
            
            // Configure window appearance for dark theme support
            window.overrideUserInterfaceStyle = .dark
            
            // Initialize and validate app container
            try AppContainer.shared.validateConfiguration()
            
            // Create and start coordinator
            let navigationController = UINavigationController()
            coordinator = AppCoordinator(navigationController: navigationController)
            coordinator?.start()
            
            // Set root view controller
            window.rootViewController = navigationController
            window.makeKeyAndVisible()
            
            // Configure state restoration
            setupStateRestoration(session: session)
            
            // Start performance monitoring
            setupPerformanceMonitoring()
            
            os_signpost(.end, log: .default, name: "SceneConfiguration", signpostID: signpostID)
            logger.info("Scene configuration completed successfully")
            
        } catch {
            logger.error("Scene configuration failed: \(error.localizedDescription)")
            os_signpost(.end, log: .default, name: "SceneConfiguration", signpostID: signpostID)
        }
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        logger.debug("Scene disconnected")
        
        // Perform cleanup
        coordinator = nil
        cancellables.removeAll()
        
        // Save state
        performStateCleanup()
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        logger.debug("Scene became active")
        
        // Resume tracking and monitoring
        coordinator?.handleSceneTransition(.active)
        performanceMonitor.startTracking()
        
        // Restore state if needed
        restoreStateIfNeeded()
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        logger.debug("Scene will resign active")
        
        // Pause tracking and save state
        coordinator?.handleSceneTransition(.inactive)
        performanceMonitor.stopTracking()
        
        // Save current state
        saveCurrentState()
    }
    
    // MARK: - Private Methods
    
    private func setupStateRestoration(session: UISceneSession) {
        window?.windowScene?.userActivity = NSUserActivity(activityType: "com.spatialtag.scene")
        window?.windowScene?.userActivity?.persistentIdentifier = session.persistentIdentifier
    }
    
    private func setupPerformanceMonitoring() {
        performanceMonitor.metricsPublisher
            .sink { [weak self] metrics in
                self?.logger.debug("Scene performance metrics: \(metrics)")
            }
            .store(in: &cancellables)
    }
    
    private func saveCurrentState() {
        guard let activity = window?.windowScene?.userActivity else { return }
        activity.addUserInfoEntries(from: ["lastActiveDate": Date()])
    }
    
    private func restoreStateIfNeeded() {
        guard let activity = window?.windowScene?.userActivity,
              let lastActiveDate = activity.userInfo?["lastActiveDate"] as? Date else {
            return
        }
        
        logger.debug("Restoring state from: \(lastActiveDate)")
    }
    
    private func performStateCleanup() {
        window?.windowScene?.userActivity = nil
        UserDefaults.standard.synchronize()
    }
}