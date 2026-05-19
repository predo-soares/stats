import SwiftUI

struct BatteryTile: View {
    let battery: BatteryStats

    var body: some View {
        MetricTile(
            title: "Battery",
            value: value,
            systemImage: "battery.75percent",
            progress: battery.level,
            detail: battery.powerSource
        )
    }

    private var value: String {
        let chargingText = battery.isCharging ? "Charging" : battery.powerSource
        return "\(StatsFormatting.percentString(battery.level)) · \(chargingText)"
    }
}
