import Foundation

struct MemoryStats {
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var used: UInt64
    var total: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var sampledPressure: Double?

    var available: UInt64 {
        total > used ? total - used : 0
    }

    var pressure: Double {
        if let sampledPressure {
            return min(max(sampledPressure, 0), 1)
        }

        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }
}
