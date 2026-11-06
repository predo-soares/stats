import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: StatsPanel!
    private var panelPresence: PanelPresence!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Bumps on every show/hide so in-flight animation completions are ignored.
    private var panelPresentationGeneration = 0
    private var isPanelPresented = false
    /// Created at launch after the status item is installed.
    private var dependencies: AppDependencies?
    private var enrollmentWindow: NSWindow?

    var usageStore: UsageStore {
        if let dependencies { return dependencies.usageStore }
        let created = AppDependencies.live()
        dependencies = created
        return created.usageStore
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Configure the process as a menu-bar agent before AppKit creates any UI.
        // LSUIElement in the generated Info.plist makes this persistent for every launch.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        let store = usageStore
        panelPresence = PanelPresence()
        panel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 760),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: StatsPanelChrome(presence: panelPresence, showsBorder: true) {
            UsageDashboardView(store: store)
        })
        if #available(macOS 13, *) {
            host.sizingOptions = [.minSize, .maxSize]
        }
        PanelPresentation.installHostingView(host, in: panel)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.alphaValue = 0

        if store.needsProviderEnrollment {
            presentProviderEnrollment(store: store)
        }
    }

    private func presentProviderEnrollment(store: UsageStore) {
        let root = ProviderEnrollmentView(store: store) { [weak self] in
            self?.enrollmentWindow?.close()
            self?.enrollmentWindow = nil
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Choose providers"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        enrollmentWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: "Token usage") {
            image.isTemplate = true
            button.image = image
        } else if let image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "Token usage") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "Usage"
        }
        button.target = self
        button.action = #selector(togglePanel)
        button.toolTip = "Token usage"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func togglePanel() {
        guard panel != nil else { return }
        if isPanelPresented { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let width = min(CGFloat(360), visible.width)
        let height = min(CGFloat(760), visible.height)
        let x = min(max(buttonFrame.maxX - width, visible.minX), visible.maxX - width)
        panel.setFrame(NSRect(x: x, y: visible.maxY - height, width: width, height: height), display: false)

        panelPresentationGeneration += 1
        let generation = panelPresentationGeneration
        isPanelPresented = true

        PanelPresentation.updateAnchor(panelPresence, panel: panel, toward: buttonFrame)
        PanelPresentation.snapCollapsed(panelPresence, panel: panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()

        PanelPresentation.animateIn(presence: panelPresence, panel: panel) { [weak self] in
            guard let self, generation == self.panelPresentationGeneration else { return }
        }
    }

    private func installEventMonitors() {
        removeEventMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hidePanel() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, self.panel.isKeyWindow {
                self.hidePanel()
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel, event.window !== self.statusItem.button?.window {
                self.hidePanel()
            }
            return event
        }
    }

    private func hidePanel() {
        guard isPanelPresented || panel.isVisible else { return }

        panelPresentationGeneration += 1
        let generation = panelPresentationGeneration
        isPanelPresented = false
        removeEventMonitors()

        PanelPresentation.animateOut(presence: panelPresence, panel: panel) { [weak self] in
            guard let self, generation == self.panelPresentationGeneration else { return }
            self.panel.orderOut(nil)
            PanelPresentation.resetAfterHide(presence: self.panelPresence, panel: self.panel)
        }
    }

    private func removeEventMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    func applicationWillTerminate(_ notification: Notification) { removeEventMonitors() }
}
