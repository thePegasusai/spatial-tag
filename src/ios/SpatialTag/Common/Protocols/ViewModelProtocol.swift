import Foundation
import Combine

/// Base protocol defining common functionality for all view models in the SpatialTag application.
/// Ensures consistent state management, error handling, and lifecycle management across features.
/// 
/// - Note: All view models must conform to this protocol to maintain consistent behavior and proper resource management.
/// - Important: The protocol is marked with @MainActor to ensure all UI updates happen on the main thread.
@MainActor
protocol ViewModelProtocol {
    // MARK: - Published Properties
    
    /// Indicates whether the view model is currently performing a loading operation
    var isLoading: Bool { get set }
    
    /// Holds any error that occurred during view model operations
    var error: Error? { get set }
    
    /// Set of cancellables for managing Combine subscriptions
    var cancellables: Set<AnyCancellable> { get set }
    
    // MARK: - Lifecycle Methods
    
    /// Called when the associated view appears
    /// Responsible for initializing resources and starting required operations
    func onAppear()
    
    /// Called when the associated view disappears
    /// Responsible for cleaning up resources and cancelling ongoing operations
    func onDisappear()
    
    /// Clears any existing error state
    func clearError()
}

// MARK: - Default Implementation
extension ViewModelProtocol {
    /// Default implementation for clearing error state
    func clearError() {
        error = nil
    }
    
    /// Default implementation for view appearance
    /// Override this method in conforming types if additional setup is needed
    func onAppear() {
        // Default implementation is empty
        // Conforming types should override this method if needed
    }
    
    /// Default implementation for view disappearance
    /// Automatically cancels all subscriptions when the view disappears
    func onDisappear() {
        // Cancel all active subscriptions
        cancellables.removeAll()
    }
}

// MARK: - Error Handling Extension
extension ViewModelProtocol {
    /// Convenience method to handle and store errors
    /// - Parameter error: The error to be stored
    func handleError(_ error: Error) {
        self.error = error
        self.isLoading = false
    }
}

// MARK: - Loading State Extension
extension ViewModelProtocol {
    /// Convenience method to update loading state
    /// - Parameter isLoading: The new loading state
    func updateLoadingState(_ isLoading: Bool) {
        self.isLoading = isLoading
    }
}

// MARK: - Task Management Extension
extension ViewModelProtocol {
    /// Convenience method to execute an async operation with automatic loading state management
    /// - Parameter operation: The async operation to execute
    /// - Returns: Void
    func executeTask(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                isLoading = true
                try await operation()
                isLoading = false
            } catch {
                handleError(error)
            }
        }
    }
}