import SwiftUI

struct UsageComparisonIndicator: View {
    let comparison: UsageTokenComparison

    var body: some View {
        switch comparison.outcome {
        case .percentage(let value):
            UsageComparisonDelta(value: value, text: String(format: "%.0f%%", abs(value)), muted: false)
        case .noPreviousUsage:
            UsageComparisonDelta(value: 1, text: "--", muted: true)
        case .noChange:
            UsageComparisonDelta(value: 0, text: "0%", muted: false)
        case .unavailable:
            UsageComparisonDelta(value: 0, text: "--", muted: true)
        }
    }
}

struct UsageComparisonDelta: View {
    let value: Double
    let text: String
    let muted: Bool

    private var color: Color {
        muted ? .secondary.opacity(0.5) : value > 0 ? .green : value < 0 ? .red : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value > 0 ? "arrow.up.right" : value < 0 ? "arrow.down.right" : "arrow.up.arrow.down")
            Text(text).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
    }
}
