import ELMUsageCore
import SwiftUI

struct PopoverMetrics: Equatable {
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    let isExpanded: Bool
}

struct UsagePopoverView: View {
    @Bindable var store: UsageStore
    let onMetricsChange: (PopoverMetrics) -> Void
    let onQuit: () -> Void

    private var isExpanded: Bool {
        store.isShowingSettings || !store.hasAPIKey
    }

    private var isSettingsVisibleInTree: Bool {
        store.isSettingsMounted || store.isShowingSettings || !store.hasAPIKey
    }

    private static let verticalPadding: CGFloat = 15

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                // Top card + error + footer: measured independently so collapsing knows the
                // exact target height immediately without removing Settings mid-animation.
                VStack(alignment: .leading, spacing: 14) {
                    contentSection

                    if let errorMessage = store.errorMessage {
                        errorBanner(message: errorMessage)
                    }

                    footerBar
                }
                .padding(.horizontal, 16)
                .padding(.top, Self.verticalPadding)
                .padding(.bottom, Self.verticalPadding)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { topHeight in
                    store.measuredCollapsedHeight = topHeight
                    reportMetrics()
                }

                if isSettingsVisibleInTree {
                    SettingsSectionView(store: store)
                        .padding(.horizontal, 16)
                        .padding(.bottom, Self.verticalPadding)
                        .opacity(isExpanded ? 1 : 0)
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                }
            }
            .frame(width: 318, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { totalHeight in
                store.measuredExpandedHeight = totalHeight
                reportMetrics()
            }
        }
        .frame(minWidth: 318, maxWidth: 318, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: isExpanded) { _, _ in
            reportMetrics()
        }
    }

    private func reportMetrics() {
        let collapsed = max(100, store.measuredCollapsedHeight)
        let expanded = max(collapsed, store.measuredExpandedHeight)
        onMetricsChange(
            PopoverMetrics(
                collapsedHeight: collapsed,
                expandedHeight: expanded,
                isExpanded: isExpanded
            )
        )
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.barColor(for: .warning))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if store.isUnauthorizedError && !store.isShowingSettings {
                Button("Update Key") {
                    store.openSettings()
                }
                .controlSize(.mini)
                .buttonStyle(.link)
                .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.barColor(for: .warning).opacity(0.10))
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        if let snapshot = store.snapshot {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .center) {
                    Text("ELM API Usage")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    percentageBadge(snapshot: snapshot)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(snapshot.formattedUsage)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text("of \(snapshot.formattedLimit)")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                ProportionalBarView(
                    fraction: snapshot.clampedFraction,
                    level: snapshot.thresholdLevel
                )

                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.isOverLimit ? "Over limit" : "Remaining")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot.formattedRemaining)
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(snapshot.isOverLimit ? Theme.barColor(for: .critical) : .primary)
                }
            }
        } else if !store.hasAPIKey {
            VStack(alignment: .leading, spacing: 4) {
                Text("ELM API Usage")
                    .font(.system(size: 14, weight: .semibold))
                Text("Connect your API key below to start tracking your balance.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if store.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Fetching ELM usage…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            Text("Unable to load usage data.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
    }

    private func percentageBadge(snapshot: UsageSnapshot) -> some View {
        let tint = Theme.barColor(for: snapshot.thresholdLevel)
        return Text(snapshot.formattedPercentage)
            .font(.system(size: 11.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                    )
            )
    }

    private var footerBar: some View {
        HStack(spacing: 6) {
            statusText

            Spacer()

            actionToolbar
        }
    }

    @ViewBuilder
    private var actionToolbar: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    toolbarButtons
                }
            }
        } else {
            HStack(spacing: 6) {
                toolbarButtons
            }
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        GlassIconButton(
            systemName: "arrow.clockwise",
            help: "Refresh now",
            isActive: false,
            isDisabled: store.isLoading
        ) {
            Task { await store.refreshNow() }
        }

        GlassIconButton(
            systemName: "gearshape",
            help: "Settings",
            isActive: store.isShowingSettings,
            isDisabled: false
        ) {
            if store.isShowingSettings {
                store.closeSettings()
            } else {
                store.openSettings()
            }
        }

        GlassIconButton(
            systemName: "power",
            help: "Quit ELM API Tracker",
            isActive: false,
            isDisabled: false
        ) {
            onQuit()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if store.isLoading {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("Updating…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        } else if let fetchedAt = store.snapshot?.fetchedAt {
            TimelineView(.periodic(from: fetchedAt, by: 30)) { context in
                Text(Self.relativeUpdateLabel(from: fetchedAt, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("elm.edina.ac.uk")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private static func relativeUpdateLabel(from date: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 15 {
            return "Updated just now"
        } else if elapsed < 60 {
            return "Updated <1m ago"
        } else {
            let minutes = elapsed / 60
            return "Updated \(minutes)m ago"
        }
    }
}

private struct GlassIconButton: View {
    let systemName: String
    let help: String
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .modifier(GlassCircleModifier(isActive: isActive))
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .help(help)
    }
}

private struct GlassCircleModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    isActive
                        ? .regular.tint(Color.primary.opacity(0.14)).interactive()
                        : .regular.interactive(),
                    in: .circle
                )
        } else {
            content
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isActive ? 0.14 : 0.06))
                )
        }
    }
}
