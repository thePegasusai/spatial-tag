import UIKit

/// Protocol defining the coordinator pattern interface for managing navigation flows and module coordination
/// in the SpatialTag application. Provides a standardized way to handle complex AR/LiDAR navigation scenarios
/// and maintain proper view controller hierarchies.
///
/// Usage:
/// - Implement this protocol in concrete coordinator classes to manage specific feature flows
/// - Use childCoordinators to maintain hierarchy of nested navigation flows
/// - Call start() to initialize and begin the coordinator's navigation sequence
protocol Coordinator: AnyObject {
    
    /// The navigation controller responsible for managing the view controller hierarchy
    /// within this coordinator's flow
    var navigationController: UINavigationController { get }
    
    /// Array of child coordinators managed by this coordinator. Used to maintain proper
    /// hierarchy and prevent memory leaks in nested navigation flows
    var childCoordinators: [Coordinator] { get set }
    
    /// Initiates the coordinator's navigation flow and sets up initial view controllers and state.
    /// This method must be implemented by all coordinator types to establish their navigation sequence.
    ///
    /// Implementation should:
    /// - Initialize the coordinator's navigation flow
    /// - Configure initial view controller hierarchy
    /// - Set up any required state or dependencies
    /// - Present initial view controller through navigation controller
    /// - Initialize and configure any required child coordinators
    func start()
}

extension Coordinator {
    /// Adds a child coordinator to the childCoordinators array
    /// - Parameter coordinator: The coordinator to add as a child
    func addChildCoordinator(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }
    
    /// Removes a child coordinator from the childCoordinators array
    /// - Parameter coordinator: The coordinator to remove
    func removeChildCoordinator(_ coordinator: Coordinator) {
        childCoordinators = childCoordinators.filter { $0 !== coordinator }
    }
    
    /// Removes all child coordinators from the childCoordinators array
    func removeAllChildCoordinators() {
        childCoordinators.removeAll()
    }
}