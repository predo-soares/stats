import SwiftUI

struct ThermalTile: View {
    let temperature: Double?
    let thermalState: ProcessInfo.ThermalState

    var body: some View {
        StatsTile(title: "Thermal", systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryValue)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(primaryColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(secondaryValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var primaryValue: String {
        temperature.map { String(format: "%.1f°C", $0) } ?? StatsFormatting.thermalStateString(thermalState)
    }

    private var secondaryValue: String {
        if temperature == nil {
            return "System thermal pressure"
        }

        return "CPU die temperature · \(StatsFormatting.thermalStateString(thermalState)) pressure"
    }

    private var systemImage: String {
        switch thermalState {
        case .nominal:
            return "thermometer.low"
        case .fair:
            return "thermometer.medium"
        case .serious, .critical:
            return "thermometer.high"
        @unknown default:
            return "thermometer.medium"
        }
    }

    private var primaryColor: Color {
        switch thermalState {
        case .nominal:
            return .primary
        case .fair:
            return .yellow
        case .serious, .critical:
            return .red
        @unknown default:
            return .primary
        }
    }
}
