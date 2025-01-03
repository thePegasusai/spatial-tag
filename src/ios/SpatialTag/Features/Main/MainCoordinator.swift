import UIKit
import SwiftUI
import OSLog
import ARKit

/// Core coordinator responsible for managing the main feature module navigation flow,
/// including AR overlay, tag interactions, and user discovery with enhanced error handling
/// and state restoration capabilities.
final class MainCoordinator: NSObject, Coordinator {
    
    // MARK: - Properties
    
    var navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    weak var parentCoordinator: Coordinator?
    
    private let mainViewModel: MainViewModel
    private let logger = Logger(subsystem: "com.spatialtag", category: "MainCoordinator")
    private let analyticsTracker: AnalyticsTracking
    private var arSession: ARSession?
    private var stateRestorationActivity: NSUserActivity?
    
    // MARK: - Initialization
    
    init(navigationController: UINavigationController,
         parentCoordinator: Coordinator?,
         mainViewModel: MainViewModel,
         analyticsTracker: AnalyticsTracking) {
        
        self.navigationController = navigationController
        self.parentCoordinator = parentCoordinator
        self.mainViewModel = mainViewModel
        self.analyticsTracker = analyticsTracker
        
        super.init()
        
        setupNotifications()
        configureStateRestoration()
    }
    
    // MARK: - Coordinator Protocol
    
    func start() {
        logger.debug("Starting main coordinator flow")
        
        let arOverlayView = AROverlayView(viewModel: mainViewModel)
        let hostingController = UIHostingController(rootView: arOverlayView)
        
        configureNavigationBar(for: hostingController)
        configureARSession()
        
        navigationController.setViewControllers([hostingController], animated: false)
        mainViewModel.startTracking()
        
        analyticsTracker.trackScreen("main_ar_view")
        setupAccessibility(for: hostingController)
        restoreStateIfNeeded()
    }
    
    // MARK: - Navigation Methods
    
    func showTagDetail(_ tag: Tag) {
        logger.debug("Showing tag detail for tag: \(tag.id)")
        
        let tagCoordinator = TagCoordinator(
            navigationController: navigationController,
            parentCoordinator: self,
            tag: tag,
            analyticsTracker: analyticsTracker
        )
        
        addChildCoordinator(tagCoordinator)
        tagCoordinator.start()
    }
    
    func showUserProfile(_ user: User) {
        logger.debug("Showing profile for user: \(user.id)")
        
        let profileCoordinator = ProfileCoordinator(
            navigationController: navigationController,
            parentCoordinator: self,
            user: user,
            analyticsTracker: analyticsTracker
        )
        
        addChildCoordinator(profileCoordinator)
        profileCoordinator.start()
    }
    
    // MARK: - AR Session Management
    
    private func configureARSession() {
        logger.debug("Configuring AR session")
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        configuration.sceneReconstruction = .mesh
        
        arSession = ARSession()
        arSession?.delegate = self
        arSession?.run(configuration)
    }
    
    func handleARSessionFailure(_ error: ARError) {
        logger.error("AR session failed: \(error.localizedDescription)")
        
        let alert = UIAlertController(
            title: "AR Session Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.configureARSession()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        navigationController.present(alert, animated: true)
        
        analyticsTracker.trackError(error)
    }
    
    // MARK: - State Restoration
    
    private func configureStateRestoration() {
        stateRestorationActivity = NSUserActivity(activityType: "com.spatialtag.main")
        stateRestorationActivity?.title = "Main AR View"
        navigationController.view.window?.windowScene?.userActivity = stateRestorationActivity
    }
    
    private func restoreStateIfNeeded() {
        guard let restorationActivity = stateRestorationActivity,
              let viewState = restorationActivity.userInfo?["viewState"] as? [String: Any] else {
            return
        }
        
        mainViewModel.restore(from: viewState)
    }
    
    // MARK: - Private Methods
    
    private func configureNavigationBar(for viewController: UIViewController) {
        viewController.navigationItem.largeTitleDisplayMode = .never
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        viewController.navigationController?.navigationBar.standardAppearance = appearance
        viewController.navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }
    
    private func setupAccessibility(for viewController: UIViewController) {
        viewController.view.accessibilityViewIsModal = true
        viewController.navigationItem.accessibilityLabel = "AR Navigation"
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        logger.warning("Received memory warning")
        
        // Pause AR session and clear caches
        arSession?.pause()
        mainViewModel.stopTracking()
        
        // Clear child coordinators
        childCoordinators.removeAll()
        
        analyticsTracker.trackEvent("memory_warning")
    }
}

// MARK: - ARSessionDelegate

extension MainCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        handleARSessionFailure(error as? ARError ?? ARError.invalidConfiguration)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        logger.warning("AR session interrupted")
        mainViewModel.stopTracking()
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        logger.debug("AR session interruption ended")
        mainViewModel.startTracking()
    }
}

// MARK: - UIStateRestoring

extension MainCoordinator: UIStateRestoring {
    func encodeRestorableState(with coder: NSCoder) {
        coder.encode(mainViewModel.currentState, forKey: "viewState")
    }
    
    func decodeRestorableState(with coder: NSCoder) {
        if let viewState = coder.decodeObject(forKey: "viewState") as? [String: Any] {
            mainViewModel.restore(from: viewState)
        }
    }
}