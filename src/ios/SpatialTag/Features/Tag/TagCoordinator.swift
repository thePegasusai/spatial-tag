// UIKit - iOS 15.0+ - Core iOS UI and navigation components
import UIKit
// SwiftUI - iOS 15.0+ - SwiftUI integration with UIKit navigation
import SwiftUI
// OSLog - iOS 15.0+ - Structured logging support
import OSLog
// Analytics - 1.0.0 - Analytics tracking functionality
import Analytics

/// Coordinator responsible for managing navigation flow and view presentation within the Tag feature module.
/// Handles transitions between tag creation, tag details, and related screens while maintaining the navigation
/// stack with comprehensive state management and accessibility support.
final class TagCoordinator: NSObject, Coordinator {
    
    // MARK: - Properties
    
    var navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    private(set) var isPresented: Bool = false
    
    private let logger = Logger(minimumLevel: .debug, category: "TagCoordinator")
    private let analytics: Analytics
    private var userActivity: NSUserActivity?
    private var restorationState: [String: Any] = [:]
    
    // MARK: - Initialization
    
    /// Initializes the tag coordinator with required dependencies
    /// - Parameters:
    ///   - navigationController: The navigation controller to manage view hierarchy
    ///   - analytics: Analytics service for tracking user interactions
    init(navigationController: UINavigationController, analytics: Analytics) {
        self.navigationController = navigationController
        self.analytics = analytics
        super.init()
        
        navigationController.delegate = self
        setupNotifications()
        configureAccessibility()
    }
    
    // MARK: - Coordinator Protocol Implementation
    
    /// Starts the coordinator's navigation flow
    func start() {
        logger.debug("Starting tag coordinator flow")
        
        let tagCreationView = TagCreationView()
        let hostingController = UIHostingController(rootView: tagCreationView)
        
        configureNavigationBar(for: hostingController)
        setupAccessibility(for: hostingController)
        
        analytics.trackScreen("tag_creation", parameters: ["source": "coordinator"])
        
        navigationController.pushViewController(hostingController, animated: true)
        isPresented = true
        
        updateRestorationState()
    }
    
    // MARK: - Navigation Methods
    
    /// Shows the tag detail view
    /// - Parameter tag: The tag to display
    func showTagDetail(_ tag: Tag) {
        logger.debug("Showing tag detail view for tag: \(tag.id)")
        
        let tagDetailView = TagDetailView(tag: tag)
        let hostingController = UIHostingController(rootView: tagDetailView)
        
        configureNavigationBar(for: hostingController)
        setupAccessibility(for: hostingController)
        
        analytics.trackScreen("tag_detail", parameters: [
            "tag_id": tag.id.uuidString,
            "creator_id": tag.creatorId.uuidString
        ])
        
        navigationController.pushViewController(hostingController, animated: true)
        updateRestorationState()
    }
    
    // MARK: - State Restoration
    
    /// Restores the navigation state after interruption
    /// - Parameter state: The state to restore from
    /// - Returns: Result indicating success or failure
    func restoreNavigationState(_ state: [String: Any]) -> Result<Void, Error> {
        logger.debug("Restoring navigation state")
        
        do {
            guard let navigationStack = state["navigationStack"] as? [String] else {
                throw NSError(domain: "TagCoordinator", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid navigation stack"
                ])
            }
            
            // Restore view hierarchy
            for identifier in navigationStack {
                switch identifier {
                case "tagCreation":
                    start()
                case "tagDetail":
                    if let tagData = state["currentTag"] as? Data,
                       let tag = try? JSONDecoder().decode(Tag.self, from: tagData) {
                        showTagDetail(tag)
                    }
                default:
                    break
                }
            }
            
            analytics.trackEvent("state_restored", parameters: [
                "screen_count": navigationStack.count
            ])
            
            return .success(())
        } catch {
            logger.error("Failed to restore state: \(error.localizedDescription)")
            return .failure(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    private func configureNavigationBar(for viewController: UIViewController) {
        viewController.navigationItem.largeTitleDisplayMode = .never
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        viewController.navigationController?.navigationBar.standardAppearance = appearance
        viewController.navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }
    
    private func setupAccessibility(for viewController: UIViewController) {
        viewController.view.accessibilityViewIsModal = true
        viewController.navigationItem.accessibilityLabel = "Tag Navigation"
    }
    
    private func updateRestorationState() {
        var navigationStack: [String] = []
        
        for viewController in navigationController.viewControllers {
            if viewController is UIHostingController<TagCreationView> {
                navigationStack.append("tagCreation")
            } else if viewController is UIHostingController<TagDetailView> {
                navigationStack.append("tagDetail")
            }
        }
        
        restorationState["navigationStack"] = navigationStack
    }
    
    @objc private func handleMemoryWarning() {
        logger.warning("Received memory warning in TagCoordinator")
        
        // Clear image caches and non-essential resources
        childCoordinators.removeAll()
        userActivity?.resignCurrent()
        userActivity = nil
        
        // Update restoration state
        updateRestorationState()
    }
}

// MARK: - UINavigationControllerDelegate

extension TagCoordinator: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        updateRestorationState()
    }
    
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        // Handle navigation completion
        if let hostingController = viewController as? UIHostingController<TagDetailView> {
            analytics.trackScreen("tag_detail_shown", parameters: nil)
        }
    }
}