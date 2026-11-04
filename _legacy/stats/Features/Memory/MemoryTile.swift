import SwiftUI

struct MemoryTile: View {
    let used: UInt64
    let total: UInt64
    let usage: Double
    var spec: String? = nil
    var isHighlighted = false
    var onTap: () -> Void = {}

    private var available: UInt64 {
        total > used ? total - used : 0
    }

    var body: some View {
        GaugeMetricTile(
            title: "Memory",
            value: StatsFormatting.percentString(usage),
            subtitle: "\(StatsFormatting.byteString(available)) available",
            systemImage: "memorychip",
            progress: usage,
            detail: spec,
            isHighlighted: isHighlighted
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
