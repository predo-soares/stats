import Foundation

struct SystemStatsSnapshot {
    var cpuUsage: Double?
    var cpuStats: CPUStats?
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryStats: MemoryStats?
    var topMemoryProcesses: [MemoryProcessStats]
    var diskUsed: UInt64
    var diskTotal: UInt64
    var networkDownloadRate: UInt64?
    var networkUploadRate: UInt64?
    var battery: BatteryStats?
    var gpuStats: GPUStats?
    var topProcesses: [RunningProcessStats]
    var lastUpdated: Date

    static let empty = SystemStatsSnapshot(
        cpuUsage: nil,
        cpuStats: nil,
        memoryUsed: 0,
        memoryTotal: ProcessInfo.processInfo.physicalMemory,
        memoryStats: nil,
        topMemoryProcesses: [],
        diskUsed: 0,
        diskTotal: 0,
        networkDownloadRate: nil,
        networkUploadRate: nil,
        battery: nil,
        gpuStats: nil,
        topProcesses: [],
        lastUpdated: Date()
    )

    var memoryUsage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskUsage: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }
}
