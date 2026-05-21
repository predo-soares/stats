import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hostingView: NSHostingView<AnyView>!
    private var cpuDetailPanel: NSPanel?
    private var memoryDetailPanel: NSPanel?
    private var diskDetailPanel: NSPanel?
    private var recentIssuesPanel: NSPanel?
    private var isCPUDetailPanelOpen = false
    private var isMemoryDetailPanelOpen = false
    private var isDiskDetailPanelOpen = false
    let store = SystemStatsStore()
    private var eventMonitor: Any?
    private var ignoreGlobalEventsUntil: Date?

    private let panelWidth: CGFloat = 460
    private let mainPanelInitialHeight: CGFloat = 400
    private let mainPanelHeight: CGFloat = 460
    private let detailPanelWidth: CGFloat = 460
    private let cpuDetailPanelHeight: CGFloat = 600
    private let standardDetailPanelHeight: CGFloat = 640
    private let margin: CGFloat = 8
    private let gap: CGFloat = 8

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        setupCPUDetailPanel()
        setupMemoryDetailPanel()
        setupDiskDetailPanel()
        setupRecentIssuesPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Stats")
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Main Panel

    private func setupPanel() {
        hostingView = NSHostingView(rootView: makeMainRootView())
        hostingView.autoresizingMask = [.width, .height]

        panel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: mainPanelInitialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
    }

    private func makeMainRootView() -> AnyView {
        AnyView(StatsPanelChrome(showsBorder: true) {
            ContentView(
                store: store,
                isCPUDetailPanelOpen: isCPUDetailPanelOpen,
                isMemoryDetailPanelOpen: isMemoryDetailPanelOpen,
                isDiskDetailPanelOpen: isDiskDetailPanelOpen,
                onIssueTap: { [weak self] issueType in
                    self?.openIssue(issueType)
                },
                onRecentIssuesTap: { [weak self] in
                    self?.toggleRecentIssuesPanel()
                },
                onCPUTap: { [weak self] in
                    self?.toggleCPUDetailPanel()
                },
                onMemoryTap: { [weak self] in
                    self?.toggleMemoryDetailPanel()
                },
                onDiskTap: { [weak self] in
                    self?.toggleDiskDetailPanel()
                }
            )
        })
    }

    private func updateMainRootView() {
        hostingView.rootView = makeMainRootView()
    }

    private func setCPUDetailPanelOpen(_ isOpen: Bool) {
        guard isCPUDetailPanelOpen != isOpen else { return }
        isCPUDetailPanelOpen = isOpen
        updateMainRootView()
    }

    private func setMemoryDetailPanelOpen(_ isOpen: Bool) {
        guard isMemoryDetailPanelOpen != isOpen else { return }
        isMemoryDetailPanelOpen = isOpen
        updateMainRootView()
    }

    private func setDiskDetailPanelOpen(_ isOpen: Bool) {
        guard isDiskDetailPanelOpen != isOpen else { return }
        isDiskDetailPanelOpen = isOpen
        updateMainRootView()
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        let currentEvent = NSApp.currentEvent

        // Hidden debug path: option-right-click logs the current instrumentation report.
        if currentEvent?.type == .rightMouseUp,
           currentEvent?.modifierFlags.contains(.option) == true {
            store.logInstrumentationSummary(reason: "status_item_dump")
            return
        }

        if panel.isVisible {
            hideAuxiliaryPanels(animated: false)
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let startedAt = DispatchTime.now().uptimeNanoseconds

        guard let button = statusItem.button else { return }

        let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleArea = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxPanelHeight = max(100, visibleArea.height - (margin * 2))
        let resolvedPanelHeight = min(mainPanelHeight, maxPanelHeight)
        let visibleX = visibleArea.maxX - panelWidth - margin
        let visibleY = visibleArea.maxY - margin - resolvedPanelHeight
        let panelFrame = NSRect(x: visibleX, y: visibleY, width: panelWidth, height: resolvedPanelHeight)

        ignoreGlobalEventsUntil = Date().addingTimeInterval(0.35)

        panel.alphaValue = 0
        panel.setFrame(panelFrame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            Task { @MainActor [weak self] in
                self?.store.recordPanelPresentation(.mainPanelPresentation, elapsedMS: elapsedMS)
            }
        })

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let ignoreUntil = self?.ignoreGlobalEventsUntil, Date() < ignoreUntil {
                    return
                }

                self?.ignoreGlobalEventsUntil = nil
                self?.hideAuxiliaryPanels(animated: true)
                self?.hidePanel()
            }
        }
    }

    private func openIssue(_ issueType: DiagnosticsIssueType) {
        switch issueType {
        case .systemUnderHeavyLoad:
            guard cpuDetailPanel?.isVisible != true else { return }
            hideAuxiliaryPanels(animated: true)
            showCPUDetailPanel()
        case .memoryPressure:
            guard memoryDetailPanel?.isVisible != true else { return }
            hideAuxiliaryPanels(animated: true)
            showMemoryDetailPanel()
        case .lowDiskSpace:
            guard diskDetailPanel?.isVisible != true else { return }
            hideAuxiliaryPanels(animated: true)
            showDiskDetailPanel()
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        })
    }

    // MARK: - CPU Detail Panel

    private func setupCPUDetailPanel() {
        let rootView = AnyView(StatsPanelChrome {
            CPUDetailView(store: store) { [weak self] in
                self?.hideCPUDetailPanel(animated: true)
            }
        })

        cpuDetailPanel = makeDetailPanel(rootView: rootView, height: cpuDetailPanelHeight)
    }

    private func toggleCPUDetailPanel() {
        guard panel.isVisible else { return }
        if cpuDetailPanel?.isVisible == true {
            hideCPUDetailPanel(animated: true)
            return
        }

        hideAuxiliaryPanels(animated: true)
        showCPUDetailPanel()
    }

    private func showCPUDetailPanel() {
        guard let detailPanel = cpuDetailPanel else { return }

        showDetailPanel(
            detailPanel,
            height: cpuDetailPanelHeight,
            presentationMetric: .cpuPanelPresentation
        ) {
            setCPUDetailPanelOpen(true)
        }
    }

    // MARK: - Memory Detail Panel

    private func setupMemoryDetailPanel() {
        let rootView = AnyView(StatsPanelChrome {
            MemoryDetailView(store: store) { [weak self] in
                self?.hideMemoryDetailPanel(animated: true)
            }
        })

        memoryDetailPanel = makeDetailPanel(rootView: rootView, height: standardDetailPanelHeight)
    }

    private func toggleMemoryDetailPanel() {
        guard panel.isVisible else { return }
        if memoryDetailPanel?.isVisible == true {
            hideMemoryDetailPanel(animated: true)
        } else {
            hideAuxiliaryPanels(animated: true)
            showMemoryDetailPanel()
        }
    }

    private func showMemoryDetailPanel() {
        guard let detailPanel = memoryDetailPanel else { return }
        showDetailPanel(detailPanel, height: standardDetailPanelHeight, presentationMetric: .memoryPanelPresentation) {
            setMemoryDetailPanelOpen(true)
        }
    }

    private func hideMemoryDetailPanel(animated: Bool) {
        setMemoryDetailPanelOpen(false)
        guard let detailPanel = memoryDetailPanel, detailPanel.isVisible else { return }
        hideDetailPanel(detailPanel, animated: animated)
    }

    // MARK: - Disk Detail Panel

    private func setupDiskDetailPanel() {
        let rootView = AnyView(StatsPanelChrome {
            DiskDetailView(store: store) { [weak self] in
                self?.hideDiskDetailPanel(animated: true)
            }
        })

        diskDetailPanel = makeDetailPanel(rootView: rootView, height: standardDetailPanelHeight)
    }

    private func toggleDiskDetailPanel() {
        guard panel.isVisible else { return }
        if diskDetailPanel?.isVisible == true {
            hideDiskDetailPanel(animated: true)
        } else {
            hideAuxiliaryPanels(animated: true)
            showDiskDetailPanel()
        }
    }

    private func showDiskDetailPanel() {
        guard let detailPanel = diskDetailPanel else { return }
        showDetailPanel(detailPanel, height: standardDetailPanelHeight, presentationMetric: .diskPanelPresentation) {
            setDiskDetailPanelOpen(true)
        }
    }

    private func hideDiskDetailPanel(animated: Bool) {
        setDiskDetailPanelOpen(false)
        guard let detailPanel = diskDetailPanel, detailPanel.isVisible else { return }
        hideDetailPanel(detailPanel, animated: animated)
    }

    // MARK: - Recent Issues Panel

    private func setupRecentIssuesPanel() {
        let rootView = AnyView(StatsPanelChrome {
            RecentIssuesDetailView(
                store: store,
                onClose: { [weak self] in
                    self?.hideRecentIssuesPanel(animated: true)
                },
                onIssueTap: { [weak self] issueType in
                    self?.hideRecentIssuesPanel(animated: false)
                    self?.openIssue(issueType)
                }
            )
        })

        recentIssuesPanel = makeDetailPanel(rootView: rootView, height: standardDetailPanelHeight)
    }

    private func toggleRecentIssuesPanel() {
        guard panel.isVisible else { return }
        if recentIssuesPanel?.isVisible == true {
            hideRecentIssuesPanel(animated: true)
        } else {
            hideAuxiliaryPanels(animated: true)
            showRecentIssuesPanel()
        }
    }

    private func showRecentIssuesPanel() {
        guard let detailPanel = recentIssuesPanel else { return }
        showDetailPanel(detailPanel, height: standardDetailPanelHeight, presentationMetric: nil) {}
    }

    private func hideRecentIssuesPanel(animated: Bool) {
        guard let detailPanel = recentIssuesPanel, detailPanel.isVisible else { return }
        hideDetailPanel(detailPanel, animated: animated)
    }

    // MARK: - Detail Panel Helpers

    private func makePanel(
        rootView: AnyView,
        width: CGFloat,
        height: CGFloat,
        level: NSWindow.Level
    ) -> NSPanel {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]

        let panel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }

    private func makeDetailPanel(rootView: AnyView, height: CGFloat) -> NSPanel {
        makePanel(
            rootView: rootView,
            width: detailPanelWidth,
            height: height,
            level: NSWindow.Level(rawValue: panel.level.rawValue + 1)
        )
    }

    private func hideAuxiliaryPanels(animated: Bool) {
        hideCPUDetailPanel(animated: animated)
        hideMemoryDetailPanel(animated: animated)
        hideDiskDetailPanel(animated: animated)
        hideRecentIssuesPanel(animated: animated)
    }

    private func showDetailPanel(
        _ detailPanel: NSPanel,
        height detailHeight: CGFloat,
        presentationMetric: SystemStatsInstrumentation.Metric?,
        onOpen: () -> Void
    ) {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let mainFrame = panel.frame
        let detailY = mainFrame.maxY - detailHeight
        let visibleX = mainFrame.minX - detailPanelWidth - gap
        let visibleFrame = NSRect(x: visibleX, y: detailY, width: detailPanelWidth, height: detailHeight)

        onOpen()

        detailPanel.alphaValue = 0
        detailPanel.setFrame(visibleFrame, display: false)
        detailPanel.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detailPanel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let presentationMetric else { return }
            let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            Task { @MainActor [weak self] in
                self?.store.recordPanelPresentation(presentationMetric, elapsedMS: elapsedMS)
            }
        })
    }

    private func hideDetailPanel(_ detailPanel: NSPanel, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                detailPanel.animator().alphaValue = 0
            }, completionHandler: { [weak detailPanel] in
                detailPanel?.orderOut(nil)
                detailPanel?.alphaValue = 1
            })
        } else {
            detailPanel.orderOut(nil)
            detailPanel.alphaValue = 1
        }
    }

    private func hideCPUDetailPanel(animated: Bool) {
        setCPUDetailPanelOpen(false)
        guard let detailPanel = cpuDetailPanel, detailPanel.isVisible else { return }
        hideDetailPanel(detailPanel, animated: animated)
    }
}
