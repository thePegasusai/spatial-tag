// SwiftUI - Core UI framework components (iOS 15.0+)
import SwiftUI
// ARKit - AR and LiDAR functionality (v6.0)
import ARKit
// Combine - Reactive programming support (latest)
import Combine

// MARK: - Constants

private enum Constants {
    static let refreshRate: TimeInterval = 1.0/30.0
    static let maxVisibleDistance: Double = 50.0
    static let minInteractionDistance: Double = 0.5
    static let batteryThreshold: Float = 0.2
    static let lidarUpdateInterval: TimeInterval = 0.1
    static let maxAnnotationsPerFrame: Int = 50
}

// MARK: - Error Types

enum AROverlayError: Error, LocalizedError {
    case sceneInitializationFailed
    case lidarUnavailable
    case lowBattery
    case performanceThresholdExceeded
    
    var errorDescription: String? {
        switch self {
        case .sceneInitializationFailed:
            return "Failed to initialize AR scene"
        case .lidarUnavailable:
            return "LiDAR sensor is not available"
        case .lowBattery:
            return "Battery level too low for AR features"
        case .performanceThresholdExceeded:
            return "Performance threshold exceeded"
        }
    }
}

// MARK: - AR Overlay View

@MainActor
struct AROverlayView: View {
    // MARK: - Properties
    
    @StateObject private var viewModel: AROverlayViewModel
    @State private var selectedTag: Tag?
    @State private var isCreatingTag: Bool = false
    @State private var errorState: AROverlayError?
    @State private var batteryLevel: Float = 1.0
    @State private var performanceMetrics = PerformanceMetrics()
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    private let sceneManager: ARSceneManager
    private let logger = Logger.shared
    
    // MARK: - Initialization
    
    init(sceneManager: ARSceneManager) {
        self.sceneManager = sceneManager
        _viewModel = StateObject(wrappedValue: AROverlayViewModel(sceneManager: sceneManager))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // AR Scene View
            ARSCNViewContainer(sceneView: sceneManager.sceneView)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    startARSession()
                }
                .onDisappear {
                    stopARSession()
                }
            
            // Tag Annotations
            ForEach(viewModel.visibleTags) { tag in
                TagAnnotationView(
                    tag: tag,
                    userLocation: viewModel.currentLocation,
                    isSelected: selectedTag?.id == tag.id
                )
                .position(viewModel.screenPosition(for: tag))
                .onTapGesture {
                    handleTagTap(tag)
                }
            }
            
            // User Annotations
            ForEach(viewModel.nearbyUsers) { user in
                UserAnnotationView(
                    user: user,
                    distance: viewModel.distance(to: user),
                    size: 120,
                    onTap: {
                        handleUserTap(user)
                    }
                )
                .position(viewModel.screenPosition(for: user))
            }
            
            // Controls Overlay
            VStack {
                // Status Bar
                HStack {
                    StatusBadgeView(status: viewModel.userStatus)
                        .accessibility(label: Text("Your status"))
                    
                    Spacer()
                    
                    // Performance Indicator
                    if performanceMetrics.batteryImpact > Constants.batteryThreshold {
                        Image(systemName: "battery.25")
                            .foregroundColor(.red)
                            .accessibility(label: Text("Low battery warning"))
                    }
                }
                .padding()
                
                Spacer()
                
                // Bottom Controls
                HStack {
                    Button(action: { isCreatingTag = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(.primary)
                    }
                    .accessibility(label: Text("Create new tag"))
                    
                    Spacer()
                    
                    Button(action: viewModel.refreshSpatialMap) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title)
                            .foregroundColor(.primary)
                    }
                    .accessibility(label: Text("Refresh AR view"))
                }
                .padding()
            }
            
            // Loading State
            if viewModel.isLoading {
                LoadingView(message: "Initializing AR...")
            }
            
            // Error State
            if let error = errorState {
                ErrorView(
                    error: error,
                    retryAction: startARSession,
                    showsBlur: !reduceTransparency
                )
            }
        }
        .sheet(isPresented: $isCreatingTag) {
            TagCreationView(
                location: viewModel.currentLocation,
                onComplete: { tag in
                    handleTagCreation(tag)
                }
            )
        }
        .onChange(of: viewModel.batteryLevel) { newLevel in
            handleBatteryLevelChange(newLevel)
        }
        .onReceive(viewModel.performancePublisher) { metrics in
            handlePerformanceUpdate(metrics)
        }
    }
    
    // MARK: - Private Methods
    
    private func startARSession() {
        Task {
            do {
                try await viewModel.startARSession()
            } catch let error as AROverlayError {
                errorState = error
            } catch {
                errorState = .sceneInitializationFailed
            }
        }
    }
    
    private func stopARSession() {
        viewModel.stopARSession()
    }
    
    private func handleTagTap(_ tag: Tag) {
        guard tag.isWithinRange(viewModel.currentLocation) else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selectedTag = tag
        viewModel.selectTag(tag)
    }
    
    private func handleUserTap(_ user: User) {
        guard viewModel.isUserVisible(user) else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.selectUser(user)
    }
    
    private func handleTagCreation(_ tag: Tag) {
        Task {
            do {
                try await viewModel.createTag(tag)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorState = .sceneInitializationFailed
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
    
    private func handleBatteryLevelChange(_ level: Float) {
        batteryLevel = level
        if level <= Constants.batteryThreshold {
            errorState = .lowBattery
        }
    }
    
    private func handlePerformanceUpdate(_ metrics: PerformanceMetrics) {
        performanceMetrics = metrics
        if metrics.processingTime > Constants.lidarUpdateInterval {
            errorState = .performanceThresholdExceeded
        }
    }
}

// MARK: - AR Scene View Container

private struct ARSCNViewContainer: UIViewRepresentable {
    let sceneView: ARSCNView
    
    func makeUIView(context: Context) -> ARSCNView {
        sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // View updates handled by ARSceneManager
    }
}

// MARK: - Preview Provider

#if DEBUG
struct AROverlayView_Previews: PreviewProvider {
    static var previews: some View {
        AROverlayView(
            sceneManager: ARSceneManager(
                sceneView: ARSCNView(),
                lidarProcessor: LiDARProcessor(
                    session: ARSession(),
                    calculator: SpatialCalculator(
                        referenceLocation: CLLocation(
                            latitude: 0,
                            longitude: 0
                        )
                    ),
                    powerMonitor: PowerMonitor()
                ),
                batteryMonitor: BatteryMonitor()
            )
        )
    }
}
#endif