// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI
// UIKit - iOS 15.0+ - Navigation and view controller management
import UIKit

/// Coordinator responsible for managing authentication flow navigation and coordination
/// between login and signup screens with accessibility support
final class AuthCoordinator: NSObject {
    // MARK: - Properties
    
    private let navigationController: UINavigationController
    private var childCoordinators: [Coordinator] = []
    private let completionHandler: (AuthCoordinator) -> Void
    private var isTransitioning: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a new authentication coordinator
    /// - Parameters:
    ///   - navigationController: The navigation controller to manage view hierarchy
    ///   - completionHandler: Closure to execute when authentication completes
    init(
        navigationController: UINavigationController,
        completionHandler: @escaping (AuthCoordinator) -> Void
    ) {
        self.navigationController = navigationController
        self.completionHandler = completionHandler
        super.init()
        
        configureNavigationBar()
    }
    
    // MARK: - Private Methods
    
    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .clear
        
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        
        // Support dark mode
        navigationController.navigationBar.tintColor = .label
    }
    
    private func announceScreenChange(_ screenName: String) {
        UIAccessibility.post(
            notification: .screenChanged,
            argument: screenName
        )
    }
}

// MARK: - Coordinator Conformance

extension AuthCoordinator: Coordinator {
    var childCoordinators: [Coordinator] {
        get { _childCoordinators }
        set { _childCoordinators = newValue }
    }
    
    var navigationController: UINavigationController {
        return _navigationController
    }
    
    func start() {
        // Create login view model and configure bindings
        let viewModel = LoginViewModel()
        
        // Create login view with view model
        let loginView = LoginView(viewModel: viewModel)
        
        // Create hosting controller
        let hostingController = UIHostingController(rootView: loginView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        
        // Configure accessibility
        hostingController.view.accessibilityIdentifier = "LoginScreen"
        
        // Push login screen
        navigationController.pushViewController(
            hostingController,
            animated: false
        )
        
        // Announce screen change for VoiceOver
        announceScreenChange("Login Screen")
    }
    
    /// Shows the signup screen with proper navigation and accessibility
    func showSignup() {
        guard !isTransitioning else { return }
        isTransitioning = true
        
        // Create signup view
        let signupView = SignupView()
        
        // Create hosting controller
        let hostingController = UIHostingController(rootView: signupView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        
        // Configure accessibility
        hostingController.view.accessibilityIdentifier = "SignupScreen"
        
        // Configure transition animation
        let transition = CATransition()
        transition.duration = 0.3
        transition.type = .push
        transition.subtype = .fromRight
        navigationController.view.layer.add(transition, forKey: nil)
        
        // Push signup screen
        navigationController.pushViewController(
            hostingController,
            animated: false
        )
        
        // Announce screen change for VoiceOver
        announceScreenChange("Signup Screen")
        
        // Reset transition state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isTransitioning = false
        }
    }
    
    /// Completes the authentication flow
    func finishAuthentication() {
        // Clear navigation stack
        navigationController.setViewControllers([], animated: false)
        
        // Remove child coordinators
        childCoordinators.removeAll()
        
        // Announce completion for VoiceOver
        UIAccessibility.post(
            notification: .announcement,
            argument: "Authentication completed"
        )
        
        // Call completion handler
        completionHandler(self)
    }
}