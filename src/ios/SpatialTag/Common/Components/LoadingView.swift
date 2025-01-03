//
// LoadingView.swift
// SpatialTag
//
// A highly accessible loading indicator component with WCAG 2.1 AA compliance
// Version: 1.0.0
// SwiftUI Version: iOS 15.0+
//

import SwiftUI

/// A customizable, accessibility-focused loading indicator view that provides
/// visual feedback during asynchronous operations
struct LoadingView: View {
    
    // MARK: - Properties
    
    /// Optional message to display below the loading indicator
    private let message: String?
    
    /// Size of the loading indicator in points
    private let size: CGFloat
    
    /// Color of the loading spinner with WCAG compliance
    private let spinnerColor: Color
    
    /// Opacity of the background overlay
    private let backgroundOpacity: Double
    
    /// Animation state for the loading spinner
    @State private var isAnimating = false
    
    // MARK: - Initialization
    
    /// Creates a new loading view with customizable appearance
    /// - Parameters:
    ///   - message: Optional text to display below the spinner
    ///   - size: Size of the loading indicator (default: 40)
    ///   - spinnerColor: Color of the spinner (default: .primary)
    ///   - backgroundOpacity: Opacity of the background overlay (default: 0.6)
    init(
        message: String? = nil,
        size: CGFloat = 40,
        spinnerColor: Color? = nil,
        backgroundOpacity: Double = 0.6
    ) {
        self.message = message
        self.size = max(size, 20) // Ensure minimum visible size
        self.spinnerColor = spinnerColor?.withAccessibilityContrast(
            against: .background,
            minimumContrast: 4.5
        ) ?? Color.primary
        self.backgroundOpacity = min(max(backgroundOpacity, 0.3), 0.9)
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background overlay with blur
            Color.background
                .opacity(backgroundOpacity)
                .blur(radius: 3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                // Loading spinner
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(spinnerColor, lineWidth: 3)
                    .frame(width: size, height: size)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1)
                        .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                
                // Optional message
                if let message = message {
                    Text(message)
                        .font(.body)
                        .foregroundColor(
                            spinnerColor.withAccessibilityContrast(
                                against: .background
                            )
                        )
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Color.background
                    .opacity(0.85)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .shadow(radius: 4)
        }
        // Accessibility modifications
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            message ?? NSLocalizedString(
                "Loading",
                comment: "Loading state accessibility label"
            )
        )
        .accessibilityValue(message ?? "")
        .accessibilityAddTraits(.isStatusElement)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityRepresentation {
            ProgressView()
        }
        // Animation trigger
        .onAppear {
            isAnimating = true
        }
        // Reduce motion support
        .environment(\.accessibilityReduceMotion, true)
        // VoiceOver announcement
        .accessibilityAnnouncement(
            message ?? NSLocalizedString(
                "Loading in progress",
                comment: "Loading state VoiceOver announcement"
            )
        )
    }
}

// MARK: - Preview Provider

#if DEBUG
struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Default loading view
            LoadingView()
            
            // Loading view with message
            LoadingView(
                message: "Loading your profile...",
                size: 50,
                spinnerColor: .blue
            )
            .preferredColorScheme(.dark)
            
            // Loading view with accessibility settings
            LoadingView(message: "Please wait...")
                .environment(\.accessibilityEnabled, true)
                .environment(\.accessibilityReduceTransparency, true)
        }
    }
}
#endif