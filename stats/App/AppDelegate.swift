import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: StatsPanel!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let dependencies = AppDependencies.live()

    var usageStore: UsageStore { dependencies.usageStore }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "Token usage")
            button.target = self
            button.action = #selector(togglePanel)
        }
        panel = StatsPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 900),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: StatsPanelChrome(showsBorder: true) {
            UsageDashboardView(store: dependencies.usageStore)
        })
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let width = min(CGFloat(420), visible.width)
        let height = min(CGFloat(900), visible.height)
        let x = min(max(buttonFrame.maxX - width, visible.minX), visible.maxX - width)
        panel.setFrame(NSRect(x: x, y: visible.maxY - height, width: width, height: height), display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
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
        panel.orderOut(nil)
        removeEventMonitors()
    }

    private func removeEventMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    func applicationWillTerminate(_ notification: Notification) { removeEventMonitors() }
}
