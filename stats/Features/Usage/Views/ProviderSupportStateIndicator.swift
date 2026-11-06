import SwiftUI

/// Color-only status icon with a native tooltip. Supported renders nothing.
struct ProviderSupportStateIndicator: View {
    let state: ProviderSupportState

    var body: some View {
        if state.showsStatusIcon {
            Image(systemName: state.statusIconSystemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.statusColor)
                .help(state.tooltip)
                .accessibilityLabel(state.accessibilityLabel)
                .accessibilityHint(state.tooltip)
        }
    }
}
