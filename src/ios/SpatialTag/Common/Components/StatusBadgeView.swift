// SwiftUI - Core UI framework for building the view (iOS 15.0+)
import SwiftUI

/// A SwiftUI view component that displays a user's status level as a visually appealing badge
/// with appropriate styling, animations, and accessibility features.
struct StatusBadgeView: View {
    // MARK: - Properties
    
    /// The user's current status level
    private let status: StatusLevel
    
    /// The size of the badge in points
    private let size: CGFloat
    
    /// Whether to show animation effects
    private let showAnimation: Bool
    
    /// Animation duration for status changes
    private let animationDuration: Double = 0.3
    
    // MARK: - Initialization
    
    /// Creates a new status badge view
    /// - Parameters:
    ///   - status: The status level to display
    ///   - size: The size of the badge in points (default: 24)
    ///   - showAnimation: Whether to show animation effects (default: true)
    init(
        status: StatusLevel,
        size: CGFloat = 24,
        showAnimation: Bool = true
    ) {
        self.status = status
        self.size = size
        self.showAnimation = showAnimation
    }
    
    // MARK: - Body
    
    var body: some View {
        Capsule()
            .fill(statusColor)
            .frame(minWidth: size * 2.5, height: size)
            .overlay(
                Text(status.description)
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, size * 0.4)
            )
            .shadow(color: statusColor.opacity(0.3), radius: 4, x: 0, y: 2)
            .animation(showAnimation ? .easeInOut(duration: animationDuration) : nil)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityHint(accessibilityHint)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
    
    // MARK: - Private Methods
    
    /// Calculates the appropriate color for the current status level
    private var statusColor: Color {
        switch status {
        case .regular:
            return Color(.systemGray2)
        case .elite:
            return Color(.systemBlue)
        case .rare:
            return Color(.systemPurple)
        }
    }
    
    /// Generates an accessibility label for the badge
    private var accessibilityLabel: String {
        "Status: \(status.description)"
    }
    
    /// Generates an accessibility hint for the badge
    private var accessibilityHint: String {
        switch status {
        case .regular:
            return "Regular status level. Earn more points to reach Elite status."
        case .elite:
            return "Elite status level. Keep earning points to reach Rare status."
        case .rare:
            return "Rare status level. You've reached the highest status!"
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct StatusBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            StatusBadgeView(status: .regular)
            StatusBadgeView(status: .elite)
            StatusBadgeView(status: .rare)
            
            StatusBadgeView(status: .elite, size: 32)
            StatusBadgeView(status: .elite, showAnimation: false)
        }
        .padding()
        .previewLayout(.sizeThatFits)
        
        VStack(spacing: 20) {
            StatusBadgeView(status: .regular)
            StatusBadgeView(status: .elite)
            StatusBadgeView(status: .rare)
        }
        .padding()
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
#endif