import ELMUsageCore
import SwiftUI

struct SettingsSectionView: View {
    @Bindable var store: UsageStore
    @FocusState private var isKeyFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .opacity(0.6)

            // API Key card
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text("ELM API Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    keySourcePill
                }

                Text(keyHelperCopy)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)

                HStack(spacing: 6) {
                    SecureField(placeholderText, text: $store.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($isKeyFieldFocused)
                        .onSubmit {
                            saveDraft()
                        }

                    saveButton

                    if store.hasKeychainKey {
                        clearButton
                    }
                }

                if let status = store.settingsStatusMessage {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )
            )

            // Launch at Login row
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Launch at Login")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.canToggleLaunchAtLogin ? .primary : .secondary)
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.launchAtLoginEnabled },
                            set: { store.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .focusEffectDisabled()
                    .disabled(!store.canToggleLaunchAtLogin)
                }

                if let loginMsg = store.launchAtLoginMessage {
                    Text(loginMsg)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)

            // Subtle threshold & cadence legend
            HStack(spacing: 10) {
                thresholdLegendItem(label: "<65%", level: .normal)
                thresholdLegendItem(label: "65–85%", level: .warning)
                thresholdLegendItem(label: "≥85%", level: .critical)
                Spacer()
                Text("Updates every 5m")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)
        }
        .onAppear {
            if !store.hasAPIKey {
                isKeyFieldFocused = true
            }
        }
    }

    private var placeholderText: String {
        store.hasKeychainKey ? "Paste a new key to replace…" : "Paste key to save in Keychain…"
    }

    private var keyHelperCopy: String {
        switch store.keySource {
        case .environment:
            return "Defaults to your ELM_API_KEY environment variable. Paste a key below to save it in Keychain instead."
        case .keychain:
            return "Saved securely in macOS Keychain. Paste a new key to replace it, or clear to fall back to ELM_API_KEY."
        case .none:
            return "Defaults to your ELM_API_KEY environment variable if set, or paste your key below to save it in Keychain."
        }
    }

    private var isDraftEmpty: Bool {
        store.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var saveButton: some View {
        if #available(macOS 26.0, *) {
            Button("Save") {
                saveDraft()
            }
            .controlSize(.small)
            .buttonStyle(.glass)
            .focusEffectDisabled()
            .disabled(isDraftEmpty)
        } else {
            Button("Save") {
                saveDraft()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .focusEffectDisabled()
            .disabled(isDraftEmpty)
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        if #available(macOS 26.0, *) {
            Button("Clear") {
                store.apiKeyDraft = ""
                store.clearKeychainKey()
            }
            .controlSize(.small)
            .buttonStyle(.glass)
            .focusEffectDisabled()
        } else {
            Button("Clear") {
                store.apiKeyDraft = ""
                store.clearKeychainKey()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .focusEffectDisabled()
        }
    }

    @ViewBuilder
    private var keySourcePill: some View {
        let (label, dotColor): (String, Color) = {
            switch store.keySource {
            case .keychain:
                return ("Saved in Keychain", Theme.barColor(for: .normal))
            case .environment:
                return ("Using ELM_API_KEY", .secondary)
            case .none:
                return ("Not set", Theme.barColor(for: .warning))
            }
        }()

        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 5.5, height: 5.5)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func thresholdLegendItem(label: String, level: ThresholdLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.barColor(for: level))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func saveDraft() {
        let value = store.apiKeyDraft
        store.apiKeyDraft = ""
        store.saveAPIKey(value)
    }
}
