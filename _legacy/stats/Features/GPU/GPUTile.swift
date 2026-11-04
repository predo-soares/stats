import SwiftUI

struct GPUTile: View {
    let stats: GPUStats?
    var spec: String? = nil

    var body: some View {
        GaugeMetricTile(
            title: "GPU",
            value: stats.map { StatsFormatting.percentString($0.utilization) } ?? "--",
            subtitle: "",
            systemImage: "cpu",
            progress: stats?.utilization,
            detail: spec
        )
    }
}
