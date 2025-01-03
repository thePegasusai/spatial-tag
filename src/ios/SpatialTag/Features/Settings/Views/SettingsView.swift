// SwiftUI - iOS 15.0+ - Core UI framework
import SwiftUI

/// A comprehensive settings view providing accessibility-compliant interface for managing
/// application preferences, device capabilities, and user session
struct SettingsView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSignOutConfirmation = false
    
    // MARK: - Constants
    
    private enum Constants {
        static let spacing: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let togglePadding: CGFloat = 12
        static let cornerRadius: CGFloat = 10
    }
    
    // MARK: - Initialization
    
    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background color with theme support
                Color.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Constants.sectionSpacing) {
                        settingsSection
                        accountSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            // Accessibility adjustments
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings Screen")
            // Loading overlay
            .overlay {
                if viewModel.isLoading {
                    LoadingView(message: "Updating settings...")
                }
            }
            // Error handling
            .overlay {
                if let error = viewModel.error {
                    ErrorView(
                        error: error,
                        retryAction: nil,
                        errorColor: .red.opacity(0.85)
                    )
                }
            }
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        Section {
            VStack(spacing: Constants.spacing) {
                // Location Services Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.isLocationEnabled },
                    set: { viewModel.updateLocationSettings($0) }
                )) {
                    Label {
                        Text("Location Services")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                    }
                }
                .accessibilityHint("Toggle location services for spatial awareness")
                
                Divider()
                
                // Notifications Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.isNotificationsEnabled },
                    set: { viewModel.updateNotificationSettings($0) }
                )) {
                    Label {
                        Text("Notifications")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.purple)
                    }
                }
                .accessibilityHint("Toggle push notifications for updates")
                
                Divider()
                
                // LiDAR Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.isLiDAREnabled },
                    set: { viewModel.updateLiDARSettings($0) }
                )) {
                    Label {
                        Text("LiDAR Scanning")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "lidar.sensor")
                            .foregroundColor(.green)
                    }
                }
                .accessibilityHint("Toggle LiDAR scanning for enhanced spatial awareness")
                
                Divider()
                
                // AR Features Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.isAREnabled },
                    set: { viewModel.updateARSettings($0) }
                )) {
                    Label {
                        Text("AR Features")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "arkit")
                            .foregroundColor(.orange)
                    }
                }
                .accessibilityHint("Toggle augmented reality features")
                
                Divider()
                
                // Dark Mode Toggle
                Toggle(isOn: Binding(
                    get: { viewModel.isDarkModeEnabled },
                    set: { viewModel.updateThemeSettings($0) }
                )) {
                    Label {
                        Text("Dark Mode")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: colorScheme == .dark ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .accessibilityHint("Toggle dark mode appearance")
            }
            .padding(Constants.togglePadding)
            .background(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feature Settings")
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        Section {
            VStack {
                Button(action: {
                    showSignOutConfirmation = true
                }) {
                    Label {
                        Text("Sign Out")
                            .foregroundColor(.red)
                    } icon: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
                .accessibilityHint("Sign out of your account")
            }
            .padding(Constants.togglePadding)
            .background(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(Color.secondary.opacity(0.1))
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Account Settings")
        .confirmationDialog(
            "Are you sure you want to sign out?",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView()
            
            SettingsView()
                .preferredColorScheme(.dark)
            
            SettingsView()
                .environment(\.dynamicTypeSize, .accessibility1)
        }
    }
}
#endif