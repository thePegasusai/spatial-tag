// Foundation - iOS 15.0+ - Basic Swift functionality
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine
// os.log - iOS 15.0+ - System logging functionality
import os.log

/// Thread-safe view model managing application settings and user preferences with performance monitoring
@MainActor
final class SettingsViewModel: ViewModelProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var isBiometricsEnabled: Bool = false
    @Published private(set) var isLocationTrackingEnabled: Bool = false
    @Published private(set) var isPushNotificationsEnabled: Bool = false
    @Published private(set) var isProfileVisible: Bool = false
    @Published private(set) var discoveryRadius: Int = 50
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    
    // MARK: - Private Properties
    
    private let settingsLock = NSLock()
    private let logger = Logger(subsystem: "com.spatialtag", category: "Settings")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private let MIN_DISCOVERY_RADIUS: Int = 1
    private let MAX_DISCOVERY_RADIUS: Int = 50
    private let SETTINGS_UPDATE_TIMEOUT: TimeInterval = 5.0
    
    // MARK: - Initialization
    
    init() {
        setupInitialState()
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    func loadCurrentSettings() async {
        isLoading = true
        settingsLock.lock()
        defer {
            settingsLock.unlock()
            isLoading = false
        }
        
        do {
            // Load biometrics state
            isBiometricsEnabled = BiometricAuthenticator.shared.isBiometricAuthenticationEnabled()
            
            // Load user preferences
            let preferences = try await UserService.shared.getUserPreferences()
            isLocationTrackingEnabled = preferences.isLocationEnabled
            isPushNotificationsEnabled = preferences.areNotificationsEnabled
            isProfileVisible = preferences.isProfileVisible
            discoveryRadius = preferences.discoveryRadius
            
            logger.debug("Settings loaded successfully")
        } catch {
            self.error = error
            logger.error("Failed to load settings: \(error.localizedDescription)")
        }
    }
    
    func toggleBiometrics(_ enabled: Bool) async {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            // Verify biometrics availability
            guard BiometricAuthenticator.shared.canUseBiometrics() else {
                throw SettingsError.biometricsNotAvailable
            }
            
            // Update biometrics state
            if BiometricAuthenticator.shared.setBiometricAuthenticationEnabled(enabled) {
                isBiometricsEnabled = enabled
                logger.debug("Biometrics state updated: \(enabled)")
            } else {
                throw SettingsError.biometricsUpdateFailed
            }
        } catch {
            self.error = error
            logger.error("Failed to toggle biometrics: \(error.localizedDescription)")
        }
    }
    
    func updateDiscoveryRadius(_ radius: Int) async {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            // Validate radius bounds
            guard radius >= MIN_DISCOVERY_RADIUS && radius <= MAX_DISCOVERY_RADIUS else {
                throw SettingsError.invalidDiscoveryRadius
            }
            
            // Update local state
            discoveryRadius = radius
            
            // Update user preferences
            try await UserService.shared.updateUserProfile(["discoveryRadius": radius])
            logger.debug("Discovery radius updated: \(radius)")
        } catch {
            self.error = error
            logger.error("Failed to update discovery radius: \(error.localizedDescription)")
        }
    }
    
    func toggleLocationTracking(_ enabled: Bool) async {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            isLocationTrackingEnabled = enabled
            try await UserService.shared.updateUserProfile(["isLocationEnabled": enabled])
            logger.debug("Location tracking state updated: \(enabled)")
        } catch {
            self.error = error
            logger.error("Failed to toggle location tracking: \(error.localizedDescription)")
        }
    }
    
    func togglePushNotifications(_ enabled: Bool) async {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            isPushNotificationsEnabled = enabled
            try await UserService.shared.updateUserProfile(["areNotificationsEnabled": enabled])
            logger.debug("Push notifications state updated: \(enabled)")
        } catch {
            self.error = error
            logger.error("Failed to toggle push notifications: \(error.localizedDescription)")
        }
    }
    
    func toggleProfileVisibility(_ visible: Bool) async {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        
        do {
            isProfileVisible = visible
            try await UserService.shared.updateUserProfile(["isProfileVisible": visible])
            logger.debug("Profile visibility updated: \(visible)")
        } catch {
            self.error = error
            logger.error("Failed to toggle profile visibility: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupInitialState() {
        Task {
            await loadCurrentSettings()
        }
    }
    
    private func setupObservers() {
        // Monitor network status for settings sync
        NetworkMonitor.shared.networkStatus
            .sink { [weak self] status in
                if case .connected = status {
                    Task { [weak self] in
                        await self?.loadCurrentSettings()
                    }
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Types

private enum SettingsError: LocalizedError {
    case biometricsNotAvailable
    case biometricsUpdateFailed
    case invalidDiscoveryRadius
    case updateFailed
    
    var errorDescription: String? {
        switch self {
        case .biometricsNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricsUpdateFailed:
            return "Failed to update biometric authentication settings"
        case .invalidDiscoveryRadius:
            return "Discovery radius must be between 1 and 50 meters"
        case .updateFailed:
            return "Failed to update settings"
        }
    }
}