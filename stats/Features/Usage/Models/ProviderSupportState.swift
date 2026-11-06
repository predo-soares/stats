import SwiftUI

/// Reliability classification for a provider source. Supported stays visually quiet;
/// Experimental and Detected use color-only icons with native tooltips.
enum ProviderSupportState: String, Sendable, CaseIterable, Equatable {
    case supported
    case experimental
    case detected

    /// Compact list shows no badge for Supported.
    var showsStatusIcon: Bool {
        switch self {
        case .supported: false
        case .experimental, .detected: true
        }
    }

    var statusIconSystemName: String {
        switch self {
        case .supported: "checkmark.circle.fill"
        case .experimental: "flask.fill"
        case .detected: "antenna.radiowaves.left.and.right"
        }
    }

    var statusColor: Color {
        switch self {
        case .supported: .secondary
        case .experimental: Color(red: 0.92, green: 0.62, blue: 0.18)
        case .detected: Color(red: 0.35, green: 0.62, blue: 0.95)
        }
    }

    var tooltip: String {
        switch self {
        case .supported:
            "Reconciled against a real account. No status badge is shown."
        case .experimental:
            "Fixture or contract coverage only. Not reconciled against a paid account."
        case .detected:
            "A local source was found, but a usable token contract is not established."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .supported: "Supported"
        case .experimental: "Experimental"
        case .detected: "Detected"
        }
    }
}
