// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI

/// A comprehensive privacy and security settings view with WCAG 2.1 Level AA compliance
struct PrivacySettingsView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: SettingsViewModel
    @State private var isBiometricsEnabled: Bool = false
    @State private var showingBiometricAlert: Bool = false
    @State private var showingLocationAlert: Bool = false
    @State private var isProcessing: Bool = false
    @State private var currentError: Error?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory
    
    private let biometricAuthenticator = BiometricAuthenticator.shared
    
    // MARK: - Initialization
    
    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _isBiometricsEnabled = State(initialValue: BiometricAuthenticator.shared.isBiometricAuthenticationEnabled())
    }
    
    // MARK: - Body
    
    var body: some View {
        Form {
            // Biometric Authentication Section
            Section {
                if biometricAuthenticator.canUseBiometrics() {
                    Toggle(isOn: $isBiometricsEnabled) {
                        HStack {
                            Label {
                                Text("Use Face ID / Touch ID")
                                    .foregroundColor(.primary)
                            } icon: {
                                Image(systemName: biometricAuthenticator.biometryType == .faceID ? "faceid" : "touchid")
                            }
                        }
                    }
                    .onChange(of: isBiometricsEnabled) { newValue in
                        showingBiometricAlert = true
                    }
                    .alert("Confirm Biometric Authentication",
                           isPresented: $showingBiometricAlert) {
                        Button("Enable", role: .none) {
                            toggleBiometrics()
                        }
                        Button("Cancel", role: .cancel) {
                            isBiometricsEnabled.toggle()
                        }
                    } message: {
                        Text("This will \(isBiometricsEnabled ? "enable" : "disable") biometric authentication for accessing sensitive data.")
                    }
                }
            } header: {
                Text("Authentication")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Biometric authentication provides an additional layer of security.")
                    .foregroundColor(.secondary)
            }
            
            // Location Privacy Section
            Section {
                Toggle(isOn: $viewModel.isLocationTrackingEnabled) {
                    Label {
                        Text("Location Sharing")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                }
                .onChange(of: viewModel.isLocationTrackingEnabled) { newValue in
                    showingLocationAlert = true
                }
                .alert("Location Privacy",
                       isPresented: $showingLocationAlert) {
                    Button("Continue", role: .none) {
                        toggleLocationSharing()
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.isLocationTrackingEnabled.toggle()
                    }
                } message: {
                    Text("Location sharing is required for core app functionality. Your location data is only shared when the app is in use.")
                }
                
                Picker("Discovery Range", selection: .constant(viewModel.discoveryRadius)) {
                    Text("5 meters").tag(5)
                    Text("10 meters").tag(10)
                    Text("25 meters").tag(25)
                    Text("50 meters").tag(50)
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.isLocationTrackingEnabled)
            } header: {
                Text("Location Privacy")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Adjust how your location is shared with nearby users.")
                    .foregroundColor(.secondary)
            }
            
            // Profile Visibility Section
            Section {
                Toggle(isOn: $viewModel.isProfileVisible) {
                    Label {
                        Text("Profile Visibility")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "person.fill")
                    }
                }
                .onChange(of: viewModel.isProfileVisible) { newValue in
                    Task {
                        await viewModel.toggleProfileVisibility(newValue)
                    }
                }
                
                Toggle(isOn: $viewModel.isPushNotificationsEnabled) {
                    Label {
                        Text("Push Notifications")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "bell.fill")
                    }
                }
                .onChange(of: viewModel.isPushNotificationsEnabled) { newValue in
                    Task {
                        await viewModel.togglePushNotifications(newValue)
                    }
                }
            } header: {
                Text("Profile & Notifications")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Control your profile visibility and notification preferences.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.large)
        .loading(isProcessing)
        .errorAlert($currentError)
        // Accessibility Modifications
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Privacy and Security Settings")
        .accessibilityHint("Adjust your privacy and security preferences")
        // Dynamic Type Support
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        // Color Scheme Adaptation
        .preferredColorScheme(colorScheme)
    }
    
    // MARK: - Private Methods
    
    private func toggleBiometrics() {
        isProcessing = true
        
        Task {
            do {
                if biometricAuthenticator.setBiometricAuthenticationEnabled(isBiometricsEnabled) {
                    // Update UI with success feedback
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    
                    // Announce change to VoiceOver
                    let announcement = "Biometric authentication \(isBiometricsEnabled ? "enabled" : "disabled")"
                    UIAccessibility.post(notification: .announcement, argument: announcement)
                } else {
                    throw BiometricError.unknown
                }
            } catch {
                currentError = error
                isBiometricsEnabled.toggle()
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            
            isProcessing = false
        }
    }
    
    private func toggleLocationSharing() {
        isProcessing = true
        
        Task {
            do {
                await viewModel.toggleLocationTracking(viewModel.isLocationTrackingEnabled)
                
                // Update UI with success feedback
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                
                // Announce change to VoiceOver
                let announcement = "Location sharing \(viewModel.isLocationTrackingEnabled ? "enabled" : "disabled")"
                UIAccessibility.post(notification: .announcement, argument: announcement)
            } catch {
                currentError = error
                viewModel.isLocationTrackingEnabled.toggle()
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            
            isProcessing = false
        }
    }
}

#if DEBUG
struct PrivacySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PrivacySettingsView()
        }
        .preferredColorScheme(.dark)
        
        NavigationView {
            PrivacySettingsView()
        }
        .environment(\.sizeCategory, .accessibilityLarge)
    }
}
#endif