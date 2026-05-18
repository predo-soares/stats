import SwiftUI

private enum NetworkTileConstants {
    static let laneBarCount = 10
    static let laneSpacing: CGFloat = 6
    static let laneRowSpacing: CGFloat = 8
    static let contentSpacing: CGFloat = 14
    static let barCornerRadius: CGFloat = 3
    static let barWidth: CGFloat = 5
    static let laneHeight: CGFloat = 40
    static let metricValueSpacing: CGFloat = 4
    static let metricRowSpacing: CGFloat = 6
    static let placeholderOpacity = 0.18
    static let activeOpacity = 0.92
    static let inactiveOpacity = 0.34
    static let minimumNormalizedValue = 0.18
}

struct NetworkTile: View {
    let downloadRate: UInt64?
    let uploadRate: UInt64?
    let history: [NetworkRateSample]
    var spec: String? = nil

    var body: some View {
        StatsTile(title: "Network", systemImage: "network", detail: spec) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: NetworkTileConstants.metricRowSpacing) {
                NetworkRateMetric(
                    title: "Up",
                    systemImage: "arrow.up",
                    value: uploadRate,
                    samples: history.map(\.uploadRate)
                )
                NetworkRateMetric(
                    title: "Down",
                    systemImage: "arrow.down",
                    value: downloadRate,
                    samples: history.map(\.downloadRate)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NetworkRateMetric: View {
    let title: String
    let systemImage: String
    let value: UInt64?
    let samples: [UInt64]

    var body: some View {
    
            
            

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.caption.weight( .medium))
                            .foregroundStyle(.secondary)
                    }
                    rateValue
                }
                Spacer(minLength: 12)
                NetworkThroughputBars(samples: samples)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rateValue: some View {
        if let value {
            let parts = rateComponents(value)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(parts.number)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(parts.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("--")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func rateComponents(_ bytesPerSec: UInt64) -> (number: String, unit: String) {
        let formatted = StatsFormatting.byteRateString(bytesPerSec)
        let parts = formatted.components(separatedBy: " ")
        guard parts.count == 2 else { return (formatted, "") }
        let unit = parts[1] == "bytes/s" ? "B/s" : parts[1]
        return (parts[0], unit)
    }
}

private struct NetworkThroughputBars: View {
    let samples: [UInt64]

    private var displayedValues: [Double] {
        let visibleSamples = Array(samples.suffix(NetworkTileConstants.laneBarCount))
        let maxValue = max(visibleSamples.max() ?? 0, 1)
        let normalized = visibleSamples.map { value in
            let ratio = Double(value) / Double(maxValue)
            return max(ratio, NetworkTileConstants.minimumNormalizedValue)
        }
        let placeholders = Array(
            repeating: 0.0,
            count: max(NetworkTileConstants.laneBarCount - normalized.count, 0)
        )
        return placeholders + normalized
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: NetworkTileConstants.laneSpacing) {
            ForEach(Array(displayedValues.enumerated()), id: \.offset) { index, value in
                let hasData = value > 0
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: NetworkTileConstants.barCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(NetworkTileConstants.inactiveOpacity))
                        .frame(
                            width: NetworkTileConstants.barWidth,
                            height: NetworkTileConstants.laneHeight
                        )
                        .opacity(NetworkTileConstants.placeholderOpacity)

                    if hasData {
                        RoundedRectangle(cornerRadius: NetworkTileConstants.barCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(NetworkTileConstants.activeOpacity))
                            .frame(
                                width: NetworkTileConstants.barWidth,
                                height: max(
                                    CGFloat(value) * NetworkTileConstants.laneHeight,
                                    NetworkTileConstants.laneHeight * CGFloat(NetworkTileConstants.minimumNormalizedValue)
                                )
                            )
                    }
                }
            }
        }
        .frame(height: NetworkTileConstants.laneHeight, alignment: .bottom)
    }
}
