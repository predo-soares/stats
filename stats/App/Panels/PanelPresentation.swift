import AppKit
import QuartzCore
import SwiftUI

/// Drives the panel chrome enter/exit. SwiftUI owns scale+opacity (reliable inside
/// `NSHostingView`); the window `alphaValue` only keeps the AppKit shadow in sync.
@MainActor @Observable
final class PanelPresence {
    var isExpanded = false
    /// Horizontal scale origin in unit space (0…1), aligned to the status item.
    var anchorX: CGFloat = 1
}

enum PanelPresentation {
    static let enterDuration: TimeInterval = 0.2
    static let exitDuration: TimeInterval = 0.14
    static let hiddenScale: CGFloat = 0.96

    /// Strong ease-out — instant start, soft settle (Emil).
    static var enterAnimation: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: enterDuration)
    }

    static var exitAnimation: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: exitDuration)
    }

    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1.0, 0.32, 1.0)

    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Stable AppKit container. Host SwiftUI as a subview — never as `contentView`.
    static func installHostingView(_ host: NSView, in panel: NSPanel) {
        guard let container = panel.contentView else { return }
        host.translatesAutoresizingMaskIntoConstraints = false
        if host.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                host.topAnchor.constraint(equalTo: container.topAnchor),
                host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        container.wantsLayer = true
    }

    static func updateAnchor(_ presence: PanelPresence, panel: NSPanel, toward buttonFrame: NSRect) {
        let panelFrame = panel.frame
        guard panelFrame.width > 0 else {
            presence.anchorX = 1
            return
        }
        presence.anchorX = min(max((buttonFrame.midX - panelFrame.minX) / panelFrame.width, 0), 1)
    }

    /// Collapse without animation so the next expand has a real from-state.
    static func snapCollapsed(_ presence: PanelPresence, panel: NSPanel) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presence.isExpanded = false
        }
        panel.alphaValue = 0
    }

    /// Expand after the hidden frame has been committed to the window server.
    /// Calling this in the same turn as `orderFront` makes the enter look instant.
    static func animateIn(
        presence: PanelPresence,
        panel: NSPanel,
        reducedMotion: Bool = prefersReducedMotion,
        completion: (() -> Void)? = nil
    ) {
        if reducedMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presence.isExpanded = true
            }
            panel.alphaValue = 1
            completion?()
            return
        }

        // Commit the collapsed frame first; animate on the next turn.
        panel.layoutIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()

        DispatchQueue.main.async {
            withAnimation(enterAnimation) {
                presence.isExpanded = true
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = enterDuration
                context.timingFunction = easeOut
                panel.animator().alphaValue = 1
            }, completionHandler: completion)
        }
    }

    static func animateOut(
        presence: PanelPresence,
        panel: NSPanel,
        reducedMotion: Bool = prefersReducedMotion,
        completion: (() -> Void)? = nil
    ) {
        if reducedMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presence.isExpanded = false
            }
            panel.alphaValue = 0
            completion?()
            return
        }

        withAnimation(exitAnimation) {
            presence.isExpanded = false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = exitDuration
            context.timingFunction = easeOut
            panel.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    static func resetAfterHide(presence: PanelPresence, panel: NSPanel) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presence.isExpanded = false
        }
        panel.alphaValue = 1
    }
}
