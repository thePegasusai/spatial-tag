//
// TagAnnotationView.swift
// SpatialTag
//
// SwiftUI view component for rendering high-contrast, accessible tag annotations in AR overlay
// Version: 1.0.0
// SwiftUI Version: iOS 15.0+
//

import SwiftUI // iOS 15.0+

// MARK: - Constants

private let ANNOTATION_SIZE: CGFloat = 60.0
private let DISTANCE_FONT_SIZE: CGFloat = 12.0
private let CONTENT_PREVIEW_LENGTH: Int = 50
private let MIN_CONTRAST_RATIO: CGFloat = 4.5
private let ANIMATION_DURATION: CGFloat = 0.3

// MARK: - Tag Annotation View

struct TagAnnotationView: View {
    // MARK: - Properties
    
    let tag: Tag
    let userLocation: Location
    let isSelected: Bool
    
    @State private var currentContrast: CGFloat = MIN_CONTRAST_RATIO
    @State private var isHighlighted: Bool = false
    
    // MARK: - Environment
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 8) {
            // Content Preview
            Text(contentPreview)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.adaptiveText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: ANNOTATION_SIZE * 1.5)
            
            // Distance Indicator
            Text(distanceText)
                .font(.system(size: DISTANCE_FONT_SIZE, weight: .semibold))
                .foregroundColor(.adaptiveText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.arOverlay)
                        .opacity(reduceTransparency ? 0.95 : 0.75)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.adaptiveBackground(colorScheme: colorScheme, isARMode: true))
                .opacity(reduceTransparency ? 0.95 : 0.85)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accent : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHighlighted ? 1.1 : 1.0)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: ANIMATION_DURATION),
            value: isHighlighted
        )
        .shadow(
            color: Color.black.opacity(0.2),
            radius: 4,
            x: 0,
            y: 2
        )
        .conditionalBlur(!tag.isWithinRange(userLocation))
        .gesture(
            TapGesture()
                .onEnded { _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation {
                        isHighlighted.toggle()
                    }
                }
        )
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(contentPreview)")
        .accessibilityValue(distanceText)
        .accessibilityHint(
            tag.isWithinRange(userLocation) ?
                "Double tap to interact with tag" :
                "Tag is out of range"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    // MARK: - Helper Methods
    
    private var distanceText: String {
        guard let distance = try? userLocation.distanceTo(tag.location).get() else {
            return "Distance unknown"
        }
        
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        
        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }
    
    private var contentPreview: String {
        let content = tag.content
        if content.count <= CONTENT_PREVIEW_LENGTH {
            return content
        }
        
        let index = content.index(content.startIndex, offsetBy: CONTENT_PREVIEW_LENGTH)
        return String(content[..<index]) + "..."
    }
    
    func updateContrast(ambientLight: CGFloat) {
        let requiredContrast = max(MIN_CONTRAST_RATIO, 7.0 - (ambientLight * 3))
        currentContrast = requiredContrast
    }
}

// MARK: - Preview Provider

#if DEBUG
struct TagAnnotationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Regular tag
            TagAnnotationView(
                tag: try! Tag(
                    creatorId: UUID(),
                    location: try! Location(
                        coordinate: .init(latitude: 0, longitude: 0),
                        altitude: 0
                    ),
                    content: "Sample tag content"
                ),
                userLocation: try! Location(
                    coordinate: .init(latitude: 0, longitude: 0),
                    altitude: 0
                ),
                isSelected: false
            )
            
            // Selected tag with long content
            TagAnnotationView(
                tag: try! Tag(
                    creatorId: UUID(),
                    location: try! Location(
                        coordinate: .init(latitude: 0, longitude: 0),
                        altitude: 0
                    ),
                    content: "This is a very long tag content that should be truncated properly in the preview"
                ),
                userLocation: try! Location(
                    coordinate: .init(latitude: 0, longitude: 0),
                    altitude: 0
                ),
                isSelected: true
            )
            .preferredColorScheme(.dark)
            
            // Accessibility preview
            TagAnnotationView(
                tag: try! Tag(
                    creatorId: UUID(),
                    location: try! Location(
                        coordinate: .init(latitude: 0, longitude: 0),
                        altitude: 0
                    ),
                    content: "Accessible tag content"
                ),
                userLocation: try! Location(
                    coordinate: .init(latitude: 0, longitude: 0),
                    altitude: 0
                ),
                isSelected: false
            )
            .environment(\.accessibilityEnabled, true)
            .environment(\.accessibilityReduceTransparency, true)
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif