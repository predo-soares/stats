import SwiftUI

struct NetworkTile: View {
    let downloadRate: UInt64?
    let uploadRate: UInt64?
    var spec: String? = nil

    var body: some View {
        StatsTile(title: "Network", systemImage: "network", detail: spec, fixedHeight: StatsTile<EmptyView>.dashboardHeight) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                NetworkRateMetric(title: "Down", systemImage: "arrow.down", value: downloadRate)
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                NetworkRateMetric(title: "Up", systemImage: "arrow.up", value: uploadRate)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
    }
}

private struct NetworkRateMetric: View {
    let title: String
    let systemImage: String
    let value: UInt64?

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let value {
                let parts = rateComponents(value)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(parts.number)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(parts.unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rateComponents(_ bytesPerSec: UInt64) -> (number: String, unit: String) {
        let formatted = StatsFormatting.byteRateString(bytesPerSec)
        let parts = formatted.components(separatedBy: " ")
        guard parts.count == 2 else { return (formatted, "") }
        return (parts[0], parts[1])
    }
}
