import Foundation

struct CPUStats {
    var user: Double
    var system: Double
    var idle: Double

    var active: Double {
        user + system
    }
}
