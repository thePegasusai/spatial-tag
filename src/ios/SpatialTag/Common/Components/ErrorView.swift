//
// ErrorView.swift
// SpatialTag
//
// A reusable SwiftUI error view component with enhanced visual hierarchy
// and accessibility features
// Version: 1.0.0
// SwiftUI Version: iOS 15.0+
//

import SwiftUI

/// A view that displays an error message with optional retry functionality and
/// enhanced visual features including blur effects and accessibility support
struct ErrorView: View {
    // MARK: - Properties
    
    private let error: Error
    private let retryAction: (() -> Void)?
    private let errorColor: Color
    private let showsBlur: Bool
    
    // MARK: - Constants
    
    private enum Constants {
        static let iconSize: CGFloat = 48
        static let spacing: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let blurRadius: CGFloat = 8
        static let backgroundOpacity: CGFloat = 0.95
        static let contentPadding: CGFloat = 24
    }
    
    // MARK: - Initialization
    
    /// Creates a new error view with customizable appearance
    /// - Parameters:
    ///   - error: The error to display
    ///   - retryAction: Optional closure to execute when retry is tapped
    ///   - errorColor: Custom color for error elements (defaults to primary)
    ///   - showsBlur: Whether to show background blur effect
    init(
        error: Error,
        retryAction: (() -> Void)? = nil,
        errorColor: Color? = nil,
        showsBlur: Bool = true
    ) {
        self.error = error
        self.retryAction = retryAction
        self.errorColor = errorColor ?? .primary
        self.showsBlur = showsBlur
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.background
                .opacity(Constants.backgroundOpacity)
                .edgesIgnoringSafeArea(.all)
                .if(showsBlur) { view in
                    view.blur(radius: Constants.blurRadius)
                }
            
            // Error content
            VStack(spacing: Constants.spacing) {
                // Error icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: Constants.iconSize))
                    .foregroundColor(errorColor)
                    .accessibilityHidden(true)
                
                // Error message
                Text(errorMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(errorColor)
                    .padding(.horizontal, Constants.contentPadding)
                    .accessibilityLabel(Text("Error: \(errorMessage)"))
                
                // Retry button if action provided
                if let retryAction = retryAction {
                    Button(action: retryAction) {
                        Text("Retry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, Constants.contentPadding)
                            .padding(.vertical, Constants.spacing)
                            .background(
                                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                                    .fill(errorColor)
                            )
                    }
                    .accessibilityHint("Double tap to try again")
                }
            }
            .padding(Constants.contentPadding)
            .background(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(Color.background)
                    .shadow(radius: Constants.blurRadius)
            )
            .padding(.horizontal, Constants.contentPadding)
        }
        // Dynamic type support
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        // Semantic accessibility container
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
    
    // MARK: - Helper Methods
    
    /// Extracts a user-friendly message from the error
    private var errorMessage: String {
        if let localizedError = error as? LocalizedError {
            return localizedError.errorDescription ??
                   localizedError.localizedDescription
        }
        return error.localizedDescription
    }
}

// MARK: - View Extension

private extension View {
    /// Conditional modifier application
    @ViewBuilder func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Basic error
            ErrorView(
                error: NSError(
                    domain: "com.spatialtag",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Something went wrong"]
                )
            )
            
            // Error with retry
            ErrorView(
                error: NSError(
                    domain: "com.spatialtag",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Network connection lost"]
                ),
                retryAction: {},
                errorColor: .red
            )
            .preferredColorScheme(.dark)
            
            // Error without blur
            ErrorView(
                error: NSError(
                    domain: "com.spatialtag",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Location access denied"]
                ),
                showsBlur: false
            )
            .environment(\.dynamicTypeSize, .accessibility1)
        }
    }
}
#endif