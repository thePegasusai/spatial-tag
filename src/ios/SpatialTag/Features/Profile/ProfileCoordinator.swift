// UIKit - iOS 15.0+ - Core UI framework
import UIKit
// SwiftUI - iOS 15.0+ - SwiftUI integration
import SwiftUI
// os.log - iOS 15.0+ - Performance logging
import os.log

/// Thread-safe coordinator managing navigation flow and memory for the Profile feature module
/// with enhanced status tracking and accessibility support
final class ProfileCoordinator: Coordinator {
    // MARK: - Properties
    
    private(set) var navigationController: UINavigationController
    private(set) var childCoordinators: [Coordinator] = []
    private let coordinatorLock = NSLock()
    private let profileViewModel: ProfileViewModel
    private let performanceLog: OSLog
    
    // MARK: - Initialization
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        self.profileViewModel = ProfileViewModel()
        self.performanceLog = OSLog(subsystem: "com.spatialtag.profile", category: "Navigation")
        
        configureNavigationBar()
        setupAccessibility()
    }
    
    // MARK: - Coordinator Protocol
    
    func start() {
        os_signpost(.begin, log: performanceLog, name: "ProfileNavigation")
        
        let profileView = ProfileView(viewModel: profileViewModel)
        let hostingController = UIHostingController(rootView: profileView)
        
        // Configure accessibility
        hostingController.view.accessibilityIdentifier = "ProfileView"
        hostingController.title = "Profile"
        
        // Configure navigation appearance
        hostingController.navigationItem.largeTitleDisplayMode = .always
        
        navigationController.pushViewController(hostingController, animated: true)
        
        os_signpost(.end, log: performanceLog, name: "ProfileNavigation")
    }
    
    // MARK: - Navigation Methods
    
    /// Shows the edit profile screen with validation and accessibility
    func showEditProfile() {
        os_signpost(.begin, log: performanceLog, name: "EditProfileNavigation")
        
        coordinatorLock.lock()
        defer { coordinatorLock.unlock() }
        
        let editProfileView = EditProfileView(
            viewModel: EditProfileViewModel(
                profile: profileViewModel.profile,
                securityContext: SecurityContext()
            )
        )
        
        let hostingController = UIHostingController(rootView: editProfileView)
        hostingController.view.accessibilityIdentifier = "EditProfileView"
        hostingController.title = "Edit Profile"
        
        let navigationController = UINavigationController(rootViewController: hostingController)
        navigationController.modalPresentationStyle = .formSheet
        
        self.navigationController.present(navigationController, animated: true)
        
        os_signpost(.end, log: performanceLog, name: "EditProfileNavigation")
    }
    
    /// Shows detailed status information with tracking
    func showStatusDetails() {
        os_signpost(.begin, log: performanceLog, name: "StatusDetailsNavigation")
        
        coordinatorLock.lock()
        defer { coordinatorLock.unlock() }
        
        let statusView = StatusBadgeView(
            status: profileViewModel.profile.statusLevel,
            size: 32,
            showAnimation: true
        )
        
        let hostingController = UIHostingController(rootView: statusView)
        hostingController.view.accessibilityIdentifier = "StatusDetailsView"
        hostingController.title = "Status Details"
        
        navigationController.pushViewController(hostingController, animated: true)
        
        os_signpost(.end, log: performanceLog, name: "StatusDetailsNavigation")
    }
    
    /// Shows wishlist management interface
    func showWishlist() {
        os_signpost(.begin, log: performanceLog, name: "WishlistNavigation")
        
        coordinatorLock.lock()
        defer { coordinatorLock.unlock() }
        
        // Wishlist view implementation would go here
        // This is a placeholder for the actual wishlist interface
        
        os_signpost(.end, log: performanceLog, name: "WishlistNavigation")
    }
    
    // MARK: - Memory Management
    
    func cleanUp() {
        coordinatorLock.lock()
        defer { coordinatorLock.unlock() }
        
        // Clean up child coordinators
        childCoordinators.forEach { coordinator in
            coordinator.cleanUp()
        }
        childCoordinators.removeAll()
        
        // Clean up view model references
        profileViewModel.cancellables.removeAll()
        
        os_signpost(.event, log: performanceLog, name: "CoordinatorCleanup")
    }
    
    // MARK: - Private Methods
    
    private func configureNavigationBar() {
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = .systemBlue
        
        // Configure navigation bar appearance for iOS 15
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
        }
    }
    
    private func setupAccessibility() {
        // Configure global accessibility settings for the profile module
        UIAccessibility.post(notification: .screenChanged, argument: "Profile Section")
    }
}

// MARK: - Error Handling

extension ProfileCoordinator {
    /// Presents error view with retry capability
    private func showError(_ error: Error, retryAction: @escaping () -> Void) {
        let errorView = ErrorView(
            error: error,
            retryAction: retryAction,
            errorColor: .systemRed
        )
        
        let hostingController = UIHostingController(rootView: errorView)
        hostingController.modalPresentationStyle = .overFullScreen
        navigationController.present(hostingController, animated: true)
    }
}