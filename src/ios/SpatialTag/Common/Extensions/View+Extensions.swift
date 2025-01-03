//
// View+Extensions.swift
// SpatialTag
//
// SwiftUI View extensions providing common modifiers and utilities for consistent UI implementation
// Version: 1.0.0
// SwiftUI Version: iOS 15.0+
//

import SwiftUI

// MARK: - View Extension
public extension View {
    /// Adds a loading overlay with accessibility support
    /// - Parameters:
    ///   - isLoading: Whether to show the loading state
    ///   - message: Optional loading message
    /// - Returns: Modified view with loading overlay
    func loading(
        _ isLoading: Bool,
        message: String? = nil
    ) -> some View {
        modifier(LoadingViewModifier(isLoading: isLoading, message: message))
    }
    
    /// Presents an error alert with haptic feedback and accessibility
    /// - Parameters:
    ///   - error: Binding to optional error
    ///   - retryAction: Optional retry action
    /// - Returns: Modified view with error handling
    func errorAlert(
        _ error: Binding<Error?>,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorViewModifier(error: error, retryAction: retryAction))
    }
    
    /// Adds a status badge with animations and accessibility
    /// - Parameters:
    ///   - status: User status level
    ///   - size: Badge size in points
    /// - Returns: Modified view with status badge
    func statusBadge(
        _ status: StatusLevel,
        size: CGFloat = 24
    ) -> some View {
        modifier(StatusBadgeModifier(status: status, size: size))
    }
    
    /// Applies theme-aware background styling with performance optimization
    /// - Returns: Modified view with adaptive background
    func adaptiveBackground() -> some View {
        modifier(AdaptiveBackgroundModifier())
    }
    
    /// Applies optimized blur effect with accessibility considerations
    /// - Parameters:
    ///   - isBlurred: Whether to apply blur
    ///   - radius: Blur radius
    /// - Returns: Modified view with conditional blur
    func conditionalBlur(
        _ isBlurred: Bool,
        radius: CGFloat = 8
    ) -> some View {
        modifier(ConditionalBlurModifier(isBlurred: isBlurred, radius: radius))
    }
}

// MARK: - Loading View Modifier
private struct LoadingViewModifier: ViewModifier {
    let isLoading: Bool
    let message: String?
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .accessibility(hidden: isLoading)
            
            if isLoading {
                LoadingView(
                    message: message,
                    backgroundOpacity: reduceTransparency ? 0.9 : 0.6
                )
                .transition(
                    reduceMotion ? .opacity : .scale.combined(with: .opacity)
                )
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
    }
}

// MARK: - Error View Modifier
private struct ErrorViewModifier: ViewModifier {
    @Binding var error: Error?
    let retryAction: (() -> Void)?
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .accessibility(hidden: error != nil)
            
            if let currentError = error {
                ErrorView(
                    error: currentError,
                    retryAction: retryAction,
                    showsBlur: !reduceTransparency
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: error != nil)
        .onChange(of: error) { newError in
            if newError != nil {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Status Badge Modifier
private struct StatusBadgeModifier: ViewModifier {
    let status: StatusLevel
    let size: CGFloat
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        content.overlay(
            StatusBadgeView(
                status: status,
                size: size,
                showAnimation: !reduceMotion
            )
            .padding(4),
            alignment: .topTrailing
        )
    }
}

// MARK: - Adaptive Background Modifier
private struct AdaptiveBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                Color.adaptiveBackground(
                    colorScheme: colorScheme,
                    isARMode: false
                )
            )
            .drawingGroup() // Performance optimization for complex backgrounds
    }
}

// MARK: - Conditional Blur Modifier
private struct ConditionalBlurModifier: ViewModifier {
    let isBlurred: Bool
    let radius: CGFloat
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    func body(content: Content) -> some View {
        content
            .blur(radius: isBlurred && !reduceTransparency ? radius : 0)
            .animation(.easeInOut(duration: 0.2), value: isBlurred)
            .accessibility(hidden: isBlurred)
    }
}