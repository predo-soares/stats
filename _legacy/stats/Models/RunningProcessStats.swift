import Foundation

struct RunningProcessStats: Identifiable, Equatable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var residentMemory: UInt64 = 0
}
