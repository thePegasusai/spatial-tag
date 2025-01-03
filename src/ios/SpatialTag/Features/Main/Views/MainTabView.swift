// SwiftUI - iOS 15.0+ - Core UI framework components
import SwiftUI
// Combine - iOS 15.0+ - Reactive programming support
import Combine

/// Primary tab-based navigation view for the Spatial Tag application with enhanced accessibility,
/// performance monitoring, and error handling capabilities.
struct MainTabView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: MainViewModel
    @State private var selectedTab: Int = 0
    @State private var isTransitioning: Bool = false
    @State private var lastError: Error?
    
    // MARK: - Environment
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    // MARK: - Constants
    
    private let tabBarHeight: CGFloat = TAB_BAR_HEIGHT
    private let transitionDuration: Double = TRANSITION_ANIMATION_DURATION
    private let batteryThreshold: Double = BATTERY_OPTIMIZATION_THRESHOLD
    
    // MARK: - Initialization
    
    init(viewModel: MainViewModel = MainViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // AR Overlay Tab
            AROverlayView()
                .tabItem {
                    Label("Discover", systemImage: "arkit")
                }
                .tag(0)
                .accessibilityLabel("AR Discovery View")
            
            // Profile Tab
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(1)
                .accessibilityLabel("User Profile")
        }
        .onChange(of: selectedTab) { newTab in
            onTabChange(newTab)
        }
        .overlay {
            if viewModel.isLoading {
                LoadingView(message: "Loading...")
                    .transition(.opacity)
            }
        }
        .alert("Error", isPresented: .constant(lastError != nil)) {
            Button("OK") {
                lastError = nil
            }
        } message: {
            if let error = lastError {
                Text(error.localizedDescription)
            }
        }
        // Performance monitoring
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        // Battery optimization
        .onChange(of: viewModel.batteryOptimizationEnabled) { enabled in
            if enabled {
                handleBatteryOptimization()
            }
        }
        // Accessibility
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.tabBar)
        .accessibilityLabel("Main Navigation")
        // Error handling
        .onChange(of: viewModel.error) { error in
            if let error = error {
                handleError(error)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func onTabChange(_ newTab: Int) {
        guard !isTransitioning else { return }
        isTransitioning = true
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Animate transition if motion not reduced
        withAnimation(reduceMotion ? nil : .easeInOut(duration: transitionDuration)) {
            // Update spatial services based on tab
            if newTab == 0 {
                viewModel.isSpatialServicesActive = true
            } else {
                viewModel.isSpatialServicesActive = false
            }
        }
        
        // Reset transition state
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
            isTransitioning = false
        }
        
        // Log analytics
        Logger.shared.info("Tab changed to: \(newTab)", category: "Navigation")
    }
    
    private func handleError(_ error: Error) {
        // Log error
        Logger.shared.error("Navigation error: \(error.localizedDescription)")
        
        // Update error state
        lastError = error
        
        // Haptic feedback for error
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    private func handleBatteryOptimization() {
        // Reduce animation complexity
        if viewModel.batteryOptimizationEnabled {
            UIView.setAnimationsEnabled(false)
        }
        
        // Log battery optimization
        Logger.shared.info("Battery optimization enabled", category: "Performance")
    }
}

// MARK: - Preview Provider

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Light mode preview
            MainTabView()
            
            // Dark mode preview
            MainTabView()
                .preferredColorScheme(.dark)
            
            // Accessibility preview
            MainTabView()
                .environment(\.accessibilityEnabled, true)
                .environment(\.accessibilityReduceMotion, true)
        }
    }
}
#endif