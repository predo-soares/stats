import AppKit
import SwiftUI

final class StatsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct StatsPanelChrome<Content: View>: View {
    var showsBorder = false
    @ViewBuilder let content: Content

    init(
        showsBorder: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
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
    }
}
