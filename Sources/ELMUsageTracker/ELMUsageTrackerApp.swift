import AppKit
import ELMUsageCore
import QuartzCore
import SwiftUI

/// Flipped clipping container so `(0, 0)` is the top-left of the popover.
/// Keeping the hosted SwiftUI view anchored at `(0, 0)` guarantees the top section never shifts
/// vertically when the popover's bottom edge animates downward or upward.
private final class FlippedClipView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class TopPinnedPopoverController<Content: View>: NSViewController {
    private let width: CGFloat
    private let hostingView: NSHostingView<Content>

    init(width: CGFloat, initialHeight: CGFloat, rootView: Content) {
        self.width = width
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)

        let container = FlippedClipView(frame: NSRect(x: 0, y: 0, width: width, height: initialHeight))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: initialHeight)
        hostingView.autoresizingMask = []
        container.addSubview(hostingView)
        self.view = container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHostedContentHeight(_ height: CGFloat) {
        let clamped = max(100, ceil(height))
        if abs(hostingView.frame.height - clamped) >= 0.5 || abs(hostingView.frame.width - width) >= 0.5 {
            // Keep origin locked at (0, 0) in flipped top-left coordinates.
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: clamped)
        }
    }
}

@main
@MainActor
final class ELMUsageTrackerApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let popoverWidth: CGFloat = 318
    private var currentPopoverHeight: CGFloat = 184
    private var canAnimatePopoverResize = false

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverController: TopPinnedPopoverController<UsagePopoverView>!
    private var store: UsageStore!

    static func main() {
        let app = NSApplication.shared
        let delegate = ELMUsageTrackerApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        store = UsageStore()
        store.onIconStateChange = { [weak self] in
            self?.updateStatusItemAppearance()
        }

        setupStatusItem()
        setupPopover()
        updateStatusItemAppearance()

        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }

    func popoverDidShow(_ notification: Notification) {
        canAnimatePopoverResize = true
    }

    func popoverDidClose(_ notification: Notification) {
        canAnimatePopoverResize = false
        store.handlePopoverDidClose()

        let collapsed = max(100, ceil(store.measuredCollapsedHeight))
        currentPopoverHeight = collapsed
        popoverController.setHostedContentHeight(collapsed)
        popover.contentSize = NSSize(width: popoverWidth, height: collapsed)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = UsagePopoverView(
            store: store,
            onMetricsChange: { [weak self] metrics in
                self?.applyPopoverMetrics(metrics)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let controller = TopPinnedPopoverController(
            width: popoverWidth,
            initialHeight: currentPopoverHeight,
            rootView: rootView
        )
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: popoverWidth, height: currentPopoverHeight)

        self.popoverController = controller
        self.popover = popover
    }

    private func applyPopoverMetrics(_ metrics: PopoverMetrics) {
        // Keep the hosted view tall enough to show Settings while expanding or fading out,
        // anchored strictly at (0, 0) inside the flipped clipping container.
        let hostedHeight = max(metrics.collapsedHeight, metrics.expandedHeight)
        popoverController.setHostedContentHeight(hostedHeight)

        let targetHeight = ceil(metrics.isExpanded ? metrics.expandedHeight : metrics.collapsedHeight)
        guard abs(targetHeight - currentPopoverHeight) >= 1 else {
            if !metrics.isExpanded {
                store.finishClosingSettingsIfNeeded()
            }
            return
        }

        currentPopoverHeight = targetHeight
        let targetSize = NSSize(width: popoverWidth, height: targetHeight)

        if popover.isShown && canAnimatePopoverResize {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.popover.contentSize = targetSize
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.store.finishClosingSettingsIfNeeded()
                    if !self.store.isSettingsMounted {
                        self.popoverController.setHostedContentHeight(self.currentPopoverHeight)
                    }
                }
            })
        } else {
            popover.contentSize = targetSize
            if !metrics.isExpanded {
                store.finishClosingSettingsIfNeeded()
                popoverController.setHostedContentHeight(targetHeight)
            }
        }
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            canAnimatePopoverResize = false
            store.refreshOnPopoverOpen()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            if let window = popover.contentViewController?.view.window {
                window.makeKey()
                if store.hasAPIKey && !store.isShowingSettings {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    private func showContextMenu() {
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(menuRefreshNow), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = !store.isLoading
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit ELM API Tracker", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuRefreshNow() {
        Task {
            await store.refreshNow()
        }
    }

    @objc private func menuOpenSettings() {
        store.openSettings()
        if !popover.isShown {
            togglePopover()
        }
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let iconState: MenuBarIconState
        if let snapshot = store.snapshot {
            iconState = .usage(
                fraction: snapshot.clampedFraction,
                isOverLimit: snapshot.isOverLimit,
                hasUsage: snapshot.usage > 0
            )
        } else if store.isLoading {
            iconState = .loading
        } else if !store.hasAPIKey {
            iconState = .missingKey
        } else if store.errorMessage != nil {
            iconState = .error
        } else {
            iconState = .loading
        }

        button.image = MenuBarIconRenderer.render(state: iconState)
        button.toolTip = store.tooltipText
    }

    /// Provides standard Cmd+C / Cmd+V / Cmd+X / Cmd+A shortcuts inside the popover's SecureField
    /// when running as a menu-bar-only (.accessory) app.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
