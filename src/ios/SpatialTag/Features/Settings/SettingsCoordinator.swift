// UIKit - iOS 15.0+ - Core UI framework
import UIKit
// SwiftUI - iOS 15.0+ - SwiftUI integration
import SwiftUI

/// Coordinator responsible for managing navigation flow and module coordination within the Settings feature.
/// Implements secure state management, accessibility support, and handles deep linking capabilities.
final class SettingsCoordinator: Coordinator {
    // MARK: - Properties
    
    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    private let onSignOut: (() -> Void)?
    private let navigationLock = NSLock()
    private let logger = Logger.shared
    
    // MARK: - State Management
    
    private let stateManager = StateRestorationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes the settings coordinator with required dependencies
    /// - Parameters:
    ///   - navigationController: The navigation controller to manage view hierarchy
    ///   - onSignOut: Optional callback to handle sign out events
    init(navigationController: UINavigationController, onSignOut: (() -> Void)? = nil) {
        self.navigationController = navigationController
        self.onSignOut = onSignOut
        
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        
        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        logger.debug("SettingsCoordinator initialized")
    }
    
    // MARK: - Coordinator Protocol
    
    func start() {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        
        // Create and configure view model
        let viewModel = SettingsViewModel()
        
        // Create settings view
        let settingsView = SettingsView(viewModel: viewModel)
        
        // Create hosting controller
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.title = "Settings"
        
        // Configure accessibility
        hostingController.view.accessibilityIdentifier = "SettingsView"
        
        // Handle sign out events
        viewModel.onSignOutRequested = { [weak self] in
            self?.handleSignOut()
        }
        
        // Push settings view controller
        navigationController.pushViewController(hostingController, animated: true)
        
        logger.debug("Settings flow started")
    }
    
    // MARK: - Navigation Methods
    
    /// Shows privacy settings screen with optional deep linking support
    /// - Parameter deepLink: Optional deep link data for specific privacy section
    func showPrivacySettings(deepLink: DeepLink? = nil) {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        
        let viewModel = PrivacySettingsViewModel()
        let privacyView = PrivacySettingsView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: privacyView)
        hostingController.title = "Privacy"
        
        // Configure deep link if present
        if let deepLink = deepLink {
            viewModel.handleDeepLink(deepLink)
        }
        
        // Update state restoration data
        stateManager.saveState(for: "privacy_settings")
        
        navigationController.pushViewController(hostingController, animated: true)
        
        logger.debug("Privacy settings presented")
    }
    
    /// Shows account settings screen
    func showAccountSettings() {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        
        let viewModel = AccountSettingsViewModel()
        let accountView = AccountSettingsView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: accountView)
        hostingController.title = "Account"
        
        // Update state restoration data
        stateManager.saveState(for: "account_settings")
        
        navigationController.pushViewController(hostingController, animated: true)
        
        logger.debug("Account settings presented")
    }
    
    // MARK: - Private Methods
    
    private func handleSignOut() {
        navigationLock.lock()
        defer { navigationLock.unlock() }
        
        // Clear sensitive data
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        KeychainManager.shared.removeToken(forKey: "auth_token")
        
        // Reset state restoration
        stateManager.clearAllState()
        
        // Execute sign out callback
        onSignOut?()
        
        // Clean up navigation stack
        navigationController.popToRootViewController(animated: true)
        removeAllChildCoordinators()
        
        logger.info("User signed out successfully")
    }
    
    @objc private func handleMemoryWarning() {
        logger.warning("Memory warning received in SettingsCoordinator")
        stateManager.clearTemporaryState()
    }
}

// MARK: - State Restoration

private class StateRestorationManager {
    private var states: [String: Any] = [:]
    
    func saveState(for identifier: String) {
        states[identifier] = Date()
    }
    
    func clearAllState() {
        states.removeAll()
    }
    
    func clearTemporaryState() {
        // Remove states older than 30 minutes
        let thirtyMinutesAgo = Date().addingTimeInterval(-1800)
        states = states.filter { (_, value) in
            guard let date = value as? Date else { return false }
            return date > thirtyMinutesAgo
        }
    }
}