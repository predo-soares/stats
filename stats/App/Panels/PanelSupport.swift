import AppKit
import SwiftUI

final class StatsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct StatsPanelChrome<Content: View>: View {
    var presence: PanelPresence
    var showsBorder = false
    @ViewBuilder let content: Content

    init(
        presence: PanelPresence,
        showsBorder: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.presence = presence
        self.showsBorder = showsBorder
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        if showsBorder {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        }
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Animate the chrome, not the NSPanel — hosting views fight CA layer transforms.
            .scaleEffect(
                presence.isExpanded ? 1 : PanelPresentation.hiddenScale,
                anchor: UnitPoint(x: presence.anchorX, y: 0)
            )
            .opacity(presence.isExpanded ? 1 : 0)
    }
}
