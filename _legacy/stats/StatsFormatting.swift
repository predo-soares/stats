import Foundation

enum StatsFormatting {
    nonisolated static func percentString(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    nonisolated static func processPercentString(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    nonisolated static func byteString(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    nonisolated static func byteRateString(_ value: UInt64) -> String {
        "\(byteString(value))/s"
    }

    nonisolated static func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}
