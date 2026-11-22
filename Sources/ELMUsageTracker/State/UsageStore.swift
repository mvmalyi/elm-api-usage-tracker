import AppKit
import ELMUsageCore
import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    static let defaultPollInterval: TimeInterval = 300 // 5 minutes
    static let clickRefreshCooldown: TimeInterval = 3

    private(set) var snapshot: UsageSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var keySource: APIKeySource = .none
    private(set) var hasKeychainKey = false
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginMessage: String?
    private(set) var settingsStatusMessage: String?

    var isShowingSettings = false
    var isSettingsMounted = false
    var apiKeyDraft = ""

    @ObservationIgnored
    var measuredCollapsedHeight: CGFloat = 184

    @ObservationIgnored
    var measuredExpandedHeight: CGFloat = 184

    @ObservationIgnored
    var onIconStateChange: (() -> Void)?

    @ObservationIgnored
    private let client: any CostsFetching

    @ObservationIgnored
    private let keychainStore: KeychainStore

    @ObservationIgnored
    private let launchAtLoginManager: LaunchAtLoginManager

    @ObservationIgnored
    private let pollInterval: TimeInterval

    @ObservationIgnored
    private var pollTask: Task<Void, Never>?

    @ObservationIgnored
    private var wakeObserver: NSObjectProtocol?

    @ObservationIgnored
    private var lastFetchAttempt: Date?

    init(
        client: any CostsFetching = CostsClient(),
        keychainStore: KeychainStore = KeychainStore(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        pollInterval: TimeInterval = UsageStore.defaultPollInterval
    ) {
        self.client = client
        self.keychainStore = keychainStore
        self.launchAtLoginManager = launchAtLoginManager
        self.pollInterval = pollInterval

        refreshKeyState()
        refreshLaunchAtLoginState()
    }

    var hasAPIKey: Bool {
        keySource != .none
    }

    var isUnauthorizedError: Bool {
        errorMessage == CostsError.unauthorized.errorDescription
    }

    var tooltipText: String {
        if let snapshot {
            return snapshot.tooltipSummary
        }
        if isLoading {
            return "ELM API Tracker — Loading…"
        }
        if !hasAPIKey {
            return "ELM API Tracker — Click to set API key"
        }
        if let errorMessage {
            return "ELM API Tracker — \(errorMessage)"
        }
        return "ELM API Tracker"
    }

    func start() {
        refreshKeyState()
        refreshLaunchAtLoginState()

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshNow()
                }
            }
        }

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.pollInterval))
                guard !Task.isCancelled else { break }
                await self.refreshNow()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func refreshOnPopoverOpen() {
        refreshKeyState()
        refreshLaunchAtLoginState()
        settingsStatusMessage = nil

        if isLoading { return }
        if let lastFetchAttempt, Date().timeIntervalSince(lastFetchAttempt) < Self.clickRefreshCooldown {
            return
        }

        Task {
            await refreshNow()
        }
    }

    func handlePopoverDidClose() {
        isShowingSettings = false
        isSettingsMounted = false
        apiKeyDraft = ""
        settingsStatusMessage = nil
    }

    func openSettings() {
        isSettingsMounted = true
        isShowingSettings = true
    }

    func closeSettings() {
        isShowingSettings = false
    }

    func finishClosingSettingsIfNeeded() {
        if !isShowingSettings && hasAPIKey {
            isSettingsMounted = false
        }
    }

    func refreshNow() async {
        if isLoading { return }

        refreshKeyState()
        let resolved = keychainStore.resolveKey()

        guard let apiKey = resolved.value else {
            isLoading = false
            snapshot = nil
            errorMessage = nil
            notifyIconChange()
            return
        }

        isLoading = true
        lastFetchAttempt = Date()
        notifyIconChange()

        do {
            let latest = try await client.fetchUsage(apiKey: apiKey)
            snapshot = latest
            errorMessage = nil
        } catch let error as CostsError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        notifyIconChange()
    }

    func saveAPIKey(_ rawKey: String) {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            settingsStatusMessage = "Enter a non-empty API key."
            return
        }

        do {
            try keychainStore.saveKey(trimmed)
            refreshKeyState()
            errorMessage = nil
            settingsStatusMessage = "Saved to macOS Keychain."
            notifyIconChange()
            Task {
                await refreshNow()
            }
        } catch {
            settingsStatusMessage = error.localizedDescription
        }
    }

    func clearKeychainKey() {
        do {
            try keychainStore.deleteKey()
            refreshKeyState()
            if !hasAPIKey {
                snapshot = nil
                errorMessage = nil
                settingsStatusMessage = "Key removed from Keychain."
                notifyIconChange()
            } else {
                settingsStatusMessage = "Keychain key cleared; using ELM_API_KEY."
                notifyIconChange()
                Task {
                    await refreshNow()
                }
            }
        } catch {
            settingsStatusMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            refreshLaunchAtLoginState()
            settingsStatusMessage = nil
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginMessage = error.localizedDescription
        }
    }

    var canToggleLaunchAtLogin: Bool {
        launchAtLoginManager.isRunningFromAppBundle
    }

    private func refreshKeyState() {
        hasKeychainKey = keychainStore.readKeychainKey() != nil
        keySource = keychainStore.resolveKey().source
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = launchAtLoginManager.isEnabled
        launchAtLoginMessage = launchAtLoginManager.statusDescription
    }

    private func notifyIconChange() {
        onIconStateChange?()
    }
}
