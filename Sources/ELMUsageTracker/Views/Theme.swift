import AppKit
import ELMUsageCore
import SwiftUI

enum Theme {
    /// Primary muted fill color for each usage threshold.
    static func barColor(for level: ThresholdLevel) -> Color {
        Color(nsColor: barNSColor(for: level))
    }

    /// Slightly brighter leading stop for a refined Liquid Glass / macOS bar gradient.
    static func barGradient(for level: ThresholdLevel) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: barLeadingNSColor(for: level)),
                Color(nsColor: barNSColor(for: level))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func barNSColor(for level: ThresholdLevel) -> NSColor {
        switch level {
        case .normal:
            // Muted sage (< 65%)
            return adaptiveNSColor(
                light: NSColor(srgbRed: 0.275, green: 0.588, blue: 0.427, alpha: 1.0),
                dark: NSColor(srgbRed: 0.365, green: 0.722, blue: 0.545, alpha: 1.0)
            )
        case .warning:
            // Warm muted amber (65% ..< 85%)
            return adaptiveNSColor(
                light: NSColor(srgbRed: 0.820, green: 0.545, blue: 0.180, alpha: 1.0),
                dark: NSColor(srgbRed: 0.906, green: 0.655, blue: 0.286, alpha: 1.0)
            )
        case .critical:
            // Muted crimson (>= 85%)
            return adaptiveNSColor(
                light: NSColor(srgbRed: 0.808, green: 0.329, blue: 0.349, alpha: 1.0),
                dark: NSColor(srgbRed: 0.894, green: 0.427, blue: 0.443, alpha: 1.0)
            )
        }
    }

    private static func barLeadingNSColor(for level: ThresholdLevel) -> NSColor {
        switch level {
        case .normal:
            return adaptiveNSColor(
                light: NSColor(srgbRed: 0.353, green: 0.678, blue: 0.510, alpha: 1.0),
                dark: NSColor(srgbRed: 0.435, green: 0.796, blue: 0.616, alpha: 1.0)
            )
        case .warning:
            return adaptiveNSColor(
                light: NSColor(srgbRed: 0.886, green: 0.643, blue: 0.267, alpha: 1.0),
                dark: NSColor(srgbRed: 0.953, green: 0.745, blue: 0.388, alpha: 1.0)
            )
        case .critical:
            return adaptiveNSColor(
                light: NSColor(srgbRed: 0.875, green: 0.416, blue: 0.424, alpha: 1.0),
                dark: NSColor(srgbRed: 0.945, green: 0.514, blue: 0.525, alpha: 1.0)
            )
        }
    }

    private static func adaptiveNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
            switch match {
            case .darkAqua, .vibrantDark:
                return dark
            default:
                return light
            }
        }
    }
}
