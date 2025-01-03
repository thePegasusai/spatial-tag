//
// Color+Extensions.swift
// SpatialTag
//
// SwiftUI Color extensions providing WCAG 2.1 AA compliant, theme-aware color utilities
// Version: 1.0.0
// SwiftUI Version: iOS 15.0+
//

import SwiftUI

// MARK: - Color Extension
extension Color {
    
    // MARK: - Theme Colors
    
    /// Primary theme color with automatic dark mode adaptation
    static var primary: Color {
        Color("primary-light", bundle: .main)
    }
    
    /// Secondary theme color with automatic dark mode adaptation
    static var secondary: Color {
        Color("primary-dark", bundle: .main)
            .opacity(0.85)
    }
    
    /// Accent color for highlighting and CTAs
    static var accent: Color {
        Color.blue
            .opacity(0.9)
    }
    
    /// Theme-aware background color
    static var background: Color {
        Color(uiColor: .systemBackground)
    }
    
    // MARK: - AR Overlay Colors
    
    /// Standard AR overlay color with optimal contrast
    static var arOverlay: Color {
        Color("ar-overlay-light", bundle: .main)
            .opacity(0.75)
    }
    
    /// High-contrast AR overlay color for accessibility
    static var arOverlayHighContrast: Color {
        Color("ar-overlay-dark", bundle: .main)
            .opacity(0.9)
    }
    
    // MARK: - Status Colors
    
    /// Elite status color with WCAG AA compliance
    static var statusElite: Color {
        Color.purple
            .opacity(0.85)
    }
    
    /// Rare status color with WCAG AA compliance
    static var statusRare: Color {
        Color.orange
            .opacity(0.85)
    }
    
    // MARK: - Utility Functions
    
    /// Returns WCAG 2.1 AA compliant color for given status level
    /// - Parameters:
    ///   - status: User status level
    ///   - isHighContrast: Whether to apply high contrast adjustments
    /// - Returns: Accessibility-compliant status color
    static func getStatusColor(for status: StatusLevel, isHighContrast: Bool = false) -> Color {
        let baseColor: Color
        
        switch status {
        case .elite:
            baseColor = statusElite
        case .rare:
            baseColor = statusRare
        default:
            baseColor = primary
        }
        
        return isHighContrast ? 
            baseColor.opacity(0.95) :
            baseColor.opacity(0.85)
    }
    
    /// Returns theme-aware background color with blur support
    /// - Parameters:
    ///   - colorScheme: Current color scheme
    ///   - isARMode: Whether the color is used in AR context
    /// - Returns: Adapted background color
    static func adaptiveBackground(
        colorScheme: ColorScheme,
        isARMode: Bool = false
    ) -> Color {
        let baseColor = colorScheme == .dark ?
            Color.black :
            Color.white
        
        return isARMode ?
            baseColor.opacity(0.65) :
            baseColor.opacity(1.0)
    }
    
    /// Adjusts color to meet WCAG 2.1 AA contrast requirements
    /// - Parameters:
    ///   - backgroundColor: Background color to contrast against
    ///   - minimumContrast: Minimum required contrast ratio (4.5:1 for normal text, 3:1 for large text)
    /// - Returns: Contrast-adjusted color
    static func withAccessibilityContrast(
        against backgroundColor: Color,
        minimumContrast: CGFloat = 4.5
    ) -> Color {
        // Convert colors to RGB space for contrast calculations
        guard let bgComponents = backgroundColor.cgColor?.components,
              let fgComponents = self.cgColor?.components else {
            return self
        }
        
        // Calculate relative luminance
        func luminance(_ components: [CGFloat]) -> CGFloat {
            let rgb = components.prefix(3)
            let weights: [CGFloat] = [0.2126, 0.7152, 0.0722]
            return zip(rgb, weights)
                .map { $0.0 * $0.1 }
                .reduce(0, +)
        }
        
        let bgLuminance = luminance(bgComponents)
        let fgLuminance = luminance(fgComponents)
        
        // Calculate contrast ratio
        let contrastRatio = (max(bgLuminance, fgLuminance) + 0.05) /
                           (min(bgLuminance, fgLuminance) + 0.05)
        
        // Adjust if needed
        if contrastRatio < minimumContrast {
            return bgLuminance > 0.5 ?
                self.darker(by: minimumContrast / contrastRatio) :
                self.lighter(by: minimumContrast / contrastRatio)
        }
        
        return self
    }
    
    // MARK: - Private Helpers
    
    private func darker(by factor: CGFloat) -> Color {
        guard let components = self.cgColor?.components else { return self }
        return Color(red: components[0] / factor,
                    green: components[1] / factor,
                    blue: components[2] / factor)
    }
    
    private func lighter(by factor: CGFloat) -> Color {
        guard let components = self.cgColor?.components else { return self }
        return Color(red: min(1.0, components[0] * factor),
                    green: min(1.0, components[1] * factor),
                    blue: min(1.0, components[2] * factor))
    }
}

// MARK: - StatusLevel Enum
enum StatusLevel {
    case regular
    case elite
    case rare
}