import AppKit
import ELMUsageCore

enum MenuBarIconState: Equatable {
    case usage(fraction: Double, isOverLimit: Bool, hasUsage: Bool)
    case missingKey
    case loading
    case error
}

enum MenuBarIconRenderer {
    static let iconSize = NSSize(width: 18, height: 18)

    /// Renders a native macOS monochrome template ring (`isTemplate = true`).
    /// Used sector is full-opacity monochrome; remaining sector is dimmer monochrome so the
    /// ratio reads clearly on both light and dark menu bars.
    static func render(state: MenuBarIconState) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 5.9
            let lineWidth: CGFloat = 3.2
            let solid = NSColor.black
            let dim = NSColor.black.withAlphaComponent(0.28)

            switch state {
            case .usage(let fraction, let isOverLimit, let hasUsage):
                let clamped = min(max(fraction, 0.0), 1.0)
                let effectiveFraction = hasUsage ? max(clamped, 0.03) : 0.0

                if effectiveFraction <= 0.0 {
                    // Empty ring (0% used) — entire ring rendered in dimmer monochrome
                    let full = NSBezierPath()
                    full.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                    full.lineWidth = lineWidth
                    dim.setStroke()
                    full.stroke()
                } else if effectiveFraction >= 0.999 {
                    // Full ring (100% or over limit)
                    let full = NSBezierPath()
                    full.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                    full.lineWidth = lineWidth
                    solid.setStroke()
                    full.stroke()

                    if isOverLimit {
                        let dotRadius: CGFloat = 1.6
                        let dotRect = NSRect(
                            x: center.x - dotRadius,
                            y: center.y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                        solid.setFill()
                        NSBezierPath(ovalIn: dotRect).fill()
                    }
                } else {
                    // Disjoint arcs with butt caps so the remaining dimmer sector stays
                    // razor-sharp and proportionally accurate even near 96–98%.
                    let startAngle: CGFloat = 90.0
                    let endAngle: CGFloat = startAngle - CGFloat(effectiveFraction) * 360.0

                    let remainingArc = NSBezierPath()
                    remainingArc.appendArc(
                        withCenter: center,
                        radius: radius,
                        startAngle: endAngle,
                        endAngle: startAngle - 360.0,
                        clockwise: true
                    )
                    remainingArc.lineWidth = lineWidth
                    remainingArc.lineCapStyle = .butt
                    dim.setStroke()
                    remainingArc.stroke()

                    let usedArc = NSBezierPath()
                    usedArc.appendArc(
                        withCenter: center,
                        radius: radius,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: true
                    )
                    usedArc.lineWidth = lineWidth
                    usedArc.lineCapStyle = .butt
                    solid.setStroke()
                    usedArc.stroke()
                }

            case .missingKey:
                let dashed = NSBezierPath()
                dashed.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                dashed.lineWidth = 2.4
                let pattern: [CGFloat] = [2.6, 2.4]
                dashed.setLineDash(pattern, count: pattern.count, phase: 0)
                NSColor.black.withAlphaComponent(0.6).setStroke()
                dashed.stroke()

            case .loading:
                let remainingArc = NSBezierPath()
                remainingArc.appendArc(withCenter: center, radius: radius, startAngle: -20, endAngle: -270, clockwise: true)
                remainingArc.lineWidth = lineWidth
                remainingArc.lineCapStyle = .butt
                dim.setStroke()
                remainingArc.stroke()

                let activeArc = NSBezierPath()
                activeArc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -20, clockwise: true)
                activeArc.lineWidth = lineWidth
                activeArc.lineCapStyle = .butt
                NSColor.black.withAlphaComponent(0.75).setStroke()
                activeArc.stroke()

            case .error:
                let track = NSBezierPath()
                track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                track.lineWidth = 2.6
                dim.setStroke()
                track.stroke()

                let dotRadius: CGFloat = 1.8
                let dotRect = NSRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                solid.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            return true
        }

        image.isTemplate = true
        return image
    }
}
