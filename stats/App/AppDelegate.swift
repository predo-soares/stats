import AppKit
import QuartzCore
import SwiftUI

final class StatsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hostingView: NSHostingView<AnyView>!
    private var cpuDetailPanel: NSPanel?
    private var cpuDetailHostingView: NSHostingView<AnyView>?
    private var memoryDetailPanel: NSPanel?
    private var memoryDetailHostingView: NSHostingView<AnyView>?
    private var diskDetailPanel: NSPanel?
    private var diskDetailHostingView: NSHostingView<AnyView>?
    private var recentIssuesPanel: NSPanel?
    private var recentIssuesHostingView: NSHostingView<AnyView>?
    private var isCPUDetailPanelOpen = false
    private var isMemoryDetailPanelOpen = false
    private var isDiskDetailPanelOpen = false
    let store = SystemStatsStore()
    private var eventMonitor: Any?
    private var ignoreGlobalEventsUntil: Date?

    private let panelWidth: CGFloat = 460
    private let mainPanelHeight: CGFloat = 620
    private let detailPanelWidth: CGFloat = 460
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
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 600),
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
        AnyView(
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
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
            hideCPUDetailPanel(animated: false)
            hideMemoryDetailPanel(animated: false)
            hideDiskDetailPanel(animated: false)
            hideRecentIssuesPanel(animated: false)
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
        let fallbackX = visibleArea.maxX - panelWidth - margin
        let fallbackButtonFrame = NSRect(
            x: fallbackX,
            y: visibleArea.maxY - 28,
            width: panelWidth,
            height: 28
        )
        let buttonFrame = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? fallbackButtonFrame
        let proposedX = buttonFrame.midX - (panelWidth / 2)
        let minX = visibleArea.minX + margin
        let maxX = visibleArea.maxX - panelWidth - margin
        let visibleX = min(max(proposedX, minX), maxX)
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
                self?.hideCPUDetailPanel(animated: true)
                self?.hideMemoryDetailPanel(animated: true)
                self?.hideDiskDetailPanel(animated: true)
                self?.hideRecentIssuesPanel(animated: true)
                self?.hidePanel()
            }
        }
    }

    private func openIssue(_ issueType: DiagnosticsIssueType) {
        switch issueType {
        case .systemUnderHeavyLoad:
            guard cpuDetailPanel?.isVisible != true else { return }
            hideMemoryDetailPanel(animated: true)
            hideDiskDetailPanel(animated: true)
            hideRecentIssuesPanel(animated: true)
            showCPUDetailPanel()
        case .memoryPressure:
            guard memoryDetailPanel?.isVisible != true else { return }
            hideCPUDetailPanel(animated: true)
            hideDiskDetailPanel(animated: true)
            hideRecentIssuesPanel(animated: true)
            showMemoryDetailPanel()
        case .lowDiskSpace:
            guard diskDetailPanel?.isVisible != true else { return }
            hideCPUDetailPanel(animated: true)
            hideMemoryDetailPanel(animated: true)
            hideRecentIssuesPanel(animated: true)
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
        let rootView = AnyView(
            CPUDetailView(store: store) { [weak self] in
                self?.hideCPUDetailPanel(animated: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )

        let hv = NSHostingView(rootView: rootView)
        hv.autoresizingMask = [.width, .height]
        cpuDetailHostingView = hv

        let detailPanel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: detailPanelWidth, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        detailPanel.contentView = hv
        detailPanel.backgroundColor = .clear
        detailPanel.isOpaque = false
        detailPanel.appearance = NSAppearance(named: .darkAqua)
        detailPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        detailPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        detailPanel.isMovable = false
        detailPanel.hasShadow = true
        cpuDetailPanel = detailPanel
    }

    private func toggleCPUDetailPanel() {
        guard panel.isVisible else { return }
        if cpuDetailPanel?.isVisible == true {
            hideCPUDetailPanel(animated: true)
        } else {
            hideMemoryDetailPanel(animated: true)
            hideDiskDetailPanel(animated: true)
            hideRecentIssuesPanel(animated: true)
            showCPUDetailPanel()
        }
    }

    private func showCPUDetailPanel() {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        guard let detailPanel = cpuDetailPanel else { return }

        // Use a fixed height — fittingSize is unreliable before first layout
        let detailHeight: CGFloat = 600
        let mainFrame = panel.frame
        let detailY = mainFrame.maxY - detailHeight

        let visibleX = mainFrame.minX - detailPanelWidth - gap
        let visibleFrame = NSRect(x: visibleX, y: detailY, width: detailPanelWidth, height: detailHeight)

        setCPUDetailPanelOpen(true)

        detailPanel.alphaValue = 0
        detailPanel.setFrame(visibleFrame, display: false)
        detailPanel.orderFront(nil)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            detailPanel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            Task { @MainActor [weak self] in
                self?.store.recordPanelPresentation(.cpuPanelPresentation, elapsedMS: elapsedMS)
            }
        })
    }

    // MARK: - Memory Detail Panel

    private func setupMemoryDetailPanel() {
        let rootView = AnyView(
            MemoryDetailView(store: store) { [weak self] in
                self?.hideMemoryDetailPanel(animated: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )

        let hv = NSHostingView(rootView: rootView)
        hv.autoresizingMask = [.width, .height]
        memoryDetailHostingView = hv

        let detailPanel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: detailPanelWidth, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        detailPanel.contentView = hv
        detailPanel.backgroundColor = .clear
        detailPanel.isOpaque = false
        detailPanel.appearance = NSAppearance(named: .darkAqua)
        detailPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        detailPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        detailPanel.isMovable = false
        detailPanel.hasShadow = true
        memoryDetailPanel = detailPanel
    }

    private func toggleMemoryDetailPanel() {
        guard panel.isVisible else { return }
        if memoryDetailPanel?.isVisible == true {
            hideMemoryDetailPanel(animated: true)
        } else {
            hideCPUDetailPanel(animated: true)
            hideDiskDetailPanel(animated: true)
            hideRecentIssuesPanel(animated: true)
            showMemoryDetailPanel()
        }
    }

    private func showMemoryDetailPanel() {
        guard let detailPanel = memoryDetailPanel else { return }
        showDetailPanel(detailPanel, height: 640, presentationMetric: .memoryPanelPresentation) {
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
        let rootView = AnyView(
            DiskDetailView(store: store) { [weak self] in
                self?.hideDiskDetailPanel(animated: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )

        let hv = NSHostingView(rootView: rootView)
        hv.autoresizingMask = [.width, .height]
        diskDetailHostingView = hv

        let detailPanel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: detailPanelWidth, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        detailPanel.contentView = hv
        detailPanel.backgroundColor = .clear
        detailPanel.isOpaque = false
        detailPanel.appearance = NSAppearance(named: .darkAqua)
        detailPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        detailPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        detailPanel.isMovable = false
        detailPanel.hasShadow = true
        diskDetailPanel = detailPanel
    }

    private func toggleDiskDetailPanel() {
        guard panel.isVisible else { return }
        if diskDetailPanel?.isVisible == true {
            hideDiskDetailPanel(animated: true)
        } else {
            hideCPUDetailPanel(animated: true)
            hideMemoryDetailPanel(animated: true)
            hideRecentIssuesPanel(animated: true)
            showDiskDetailPanel()
        }
    }

    private func showDiskDetailPanel() {
        guard let detailPanel = diskDetailPanel else { return }
        showDetailPanel(detailPanel, height: 640, presentationMetric: .diskPanelPresentation) {
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
        let rootView = AnyView(
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
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )

        let hv = NSHostingView(rootView: rootView)
        hv.autoresizingMask = [.width, .height]
        recentIssuesHostingView = hv

        let detailPanel = StatsPanel(
            contentRect: NSRect(x: 0, y: 0, width: detailPanelWidth, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        detailPanel.contentView = hv
        detailPanel.backgroundColor = .clear
        detailPanel.isOpaque = false
        detailPanel.appearance = NSAppearance(named: .darkAqua)
        detailPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        detailPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        detailPanel.isMovable = false
        detailPanel.hasShadow = true
        recentIssuesPanel = detailPanel
    }

    private func toggleRecentIssuesPanel() {
        guard panel.isVisible else { return }
        if recentIssuesPanel?.isVisible == true {
            hideRecentIssuesPanel(animated: true)
        } else {
            hideCPUDetailPanel(animated: true)
            hideMemoryDetailPanel(animated: true)
            hideDiskDetailPanel(animated: true)
            showRecentIssuesPanel()
        }
    }

    private func showRecentIssuesPanel() {
        guard let detailPanel = recentIssuesPanel else { return }
        showDetailPanel(detailPanel, height: 640, presentationMetric: nil) {}
    }

    private func hideRecentIssuesPanel(animated: Bool) {
        guard let detailPanel = recentIssuesPanel, detailPanel.isVisible else { return }
        hideDetailPanel(detailPanel, animated: animated)
    }

    // MARK: - Detail Panel Helpers

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
        }
    }
}
