import ELMUsageCore
import SwiftUI

struct ProportionalBarView: View {
    let fraction: Double
    let level: ThresholdLevel

    private var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let fillWidth = clampedFraction > 0
                ? max(height * 0.65, width * clampedFraction)
                : 0

            ZStack(alignment: .leading) {
                // Recessed native translucent track
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )

                // Dynamic threshold fill with subtle top highlight
                if fillWidth > 0 {
                    Capsule(style: .continuous)
                        .fill(Theme.barGradient(for: level))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.32), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .frame(width: min(fillWidth, width))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: clampedFraction)
        }
        .frame(height: 10)
        .accessibilityLabel("API usage progress bar")
        .accessibilityValue("\(Int((clampedFraction * 100).rounded())) percent used")
    }
}
