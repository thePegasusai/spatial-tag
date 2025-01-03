// SwiftUI - Core UI framework components (iOS 15.0+)
import SwiftUI

/// A SwiftUI view component for displaying user annotations in the AR overlay
/// with adaptive styling, accessibility support, and optimized performance.
struct UserAnnotationView: View {
    // MARK: - Properties
    
    /// The user to display in the annotation
    private let user: User
    
    /// Distance to the user in meters
    private let distance: Double
    
    /// Size of the annotation in points
    private let size: CGFloat
    
    /// Optional tap handler
    private let onTap: (() -> Void)?
    
    /// Animation state for pulsing effect
    @State private var isAnimating = false
    
    /// Environment values for accessibility and theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Constants
    
    private enum Constants {
        static let animationDuration: Double = 1.5
        static let pulseScale: CGFloat = 1.1
        static let imageSize: CGFloat = 0.6 // 60% of container
        static let spacing: CGFloat = 8
        static let cornerRadius: CGFloat = 12
        static let minScale: CGFloat = 0.8
        static let maxScale: CGFloat = 1.2
    }
    
    // MARK: - Initialization
    
    /// Creates a new user annotation view
    /// - Parameters:
    ///   - user: The user to display
    ///   - distance: Distance to the user in meters
    ///   - size: Size of the annotation
    ///   - onTap: Optional tap handler
    init(
        user: User,
        distance: Double,
        size: CGFloat,
        onTap: (() -> Void)? = nil
    ) {
        self.user = user
        self.distance = distance
        self.size = size
        self.onTap = onTap
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: Constants.spacing) {
            // Profile image with status badge
            ZStack {
                Circle()
                    .fill(Color.adaptiveBackground(colorScheme: colorScheme, isARMode: true))
                    .frame(width: size * Constants.imageSize,
                           height: size * Constants.imageSize)
                    .shadow(radius: 4)
                
                // Animated pulse effect for active users
                if user.profile.isVisible && !reduceMotion {
                    Circle()
                        .stroke(Color.getStatusColor(for: user.profile.statusLevel),
                               lineWidth: 2)
                        .frame(width: size * Constants.imageSize,
                               height: size * Constants.imageSize)
                        .scaleEffect(isAnimating ? Constants.pulseScale : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeInOut(duration: Constants.animationDuration)
                            .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }
            }
            .statusBadge(user.profile.statusLevel, size: size * 0.3)
            
            // User name and distance
            VStack(spacing: 4) {
                Text(user.profile.displayName)
                    .font(.system(size: size * 0.25, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(distanceText)
                    .font(.system(size: size * 0.2))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size)
        .padding(.vertical, Constants.spacing)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.adaptiveBackground(colorScheme: colorScheme, isARMode: true))
                .shadow(radius: 8)
        )
        // Tap gesture
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?()
        }
        // Distance-based scaling
        .scaleEffect(calculateScale())
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        // Animation trigger
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Formats the distance for display
    private var distanceText: String {
        if distance < 1000 {
            return String(format: "%.1fm", distance)
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    /// Calculates scale based on distance
    private func calculateScale() -> CGFloat {
        let scale = 1.0 - (distance / 50.0) // Scale down as distance increases
        return min(max(scale, Constants.minScale), Constants.maxScale)
    }
    
    /// Generates accessibility label
    private var accessibilityLabel: String {
        "\(user.profile.displayName), \(user.profile.statusLevel.description) status"
    }
    
    /// Generates accessibility value
    private var accessibilityValue: String {
        "\(distanceText) away"
    }
}

// MARK: - Preview Provider

#if DEBUG
struct UserAnnotationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Regular user preview
            UserAnnotationView(
                user: previewUser(status: .regular),
                distance: 15.5,
                size: 120
            )
            
            // Elite user preview
            UserAnnotationView(
                user: previewUser(status: .elite),
                distance: 5.2,
                size: 120
            )
            .preferredColorScheme(.dark)
            
            // Rare user preview with reduced motion
            UserAnnotationView(
                user: previewUser(status: .rare),
                distance: 25.8,
                size: 120
            )
            .environment(\.accessibilityReduceMotion, true)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
    
    // Preview helper
    private static func previewUser(status: StatusLevel) -> User {
        let user = User(id: UUID(), email: "test@example.com", displayName: "Test User")
        user.profile.updateStatus(pointsEarned: status.pointThreshold)
        return user
    }
}
#endif