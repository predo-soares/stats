import Foundation

enum DiagnosticsIssueSeverity: String, Codable, CaseIterable {
    case warning
    case critical

    nonisolated var sortPriority: Int {
        switch self {
        case .critical:
            return 2
        case .warning:
            return 1
        }
    }

    nonisolated var label: String {
        rawValue.capitalized
    }
}

enum DiagnosticsIssueType: String, Codable, CaseIterable, Hashable {
    case systemUnderHeavyLoad = "system_under_heavy_load"
    case memoryPressure = "memory_pressure"
    case lowDiskSpace = "low_disk_space"

    nonisolated var title: String {
        switch self {
        case .systemUnderHeavyLoad:
            return "System Under Heavy Load"
        case .memoryPressure:
            return "Memory Pressure"
        case .lowDiskSpace:
            return "Low Disk Space"
        }
    }
}

enum DiagnosticsRuleID: String, Codable, CaseIterable {
    case cpuSaturation = "cpu_saturation"
    case thermalStress = "thermal_stress"
    case memoryStress = "memory_stress"
    case swapGrowth = "swap_growth"
    case lowDisk = "low_disk"
}

enum DiagnosticsIssueStatus: String, Codable {
    case active
    case resolved
}

enum DiagnosticsProcessClass: String, Codable {
    case foregroundApp
    case mixedWorkload
    case backgroundSystem
}

struct DiagnosticsIssueContributor: Codable, Hashable {
    var name: String
    var detail: String
}

struct DiagnosticsContextSnapshot: Codable, Hashable {
    var timestamp: Date
    var cpuUsage: Double?
    var thermalState: String
    var memoryPressureScore: Double?
    var swapUsedBytes: UInt64?
    var diskFreeBytes: UInt64?
    var diskFreeRatio: Double?
    var contributors: [DiagnosticsIssueContributor]
}

struct DiagnosticsIssueEvent: Identifiable, Codable, Hashable {
    var id: String
    var type: DiagnosticsIssueType
    var status: DiagnosticsIssueStatus
    var severity: DiagnosticsIssueSeverity
    var title: String
    var suggestedAction: String
    var contributingRuleIDs: [DiagnosticsRuleID]
    var openedAt: Date
    var lastSeenAt: Date
    var resolvedAt: Date?
    var context: DiagnosticsContextSnapshot

    nonisolated var isActionable: Bool {
        !suggestedAction.isEmpty
    }
}

struct DiagnosticsIssueDraft: Hashable {
    var type: DiagnosticsIssueType
    var severity: DiagnosticsIssueSeverity
    var title: String
    var suggestedAction: String
    var contributingRuleIDs: [DiagnosticsRuleID]
    var context: DiagnosticsContextSnapshot
}

struct DiagnosticsMemorySignal: Hashable {
    var timestamp: Date
    var usageRatio: Double
    var compressedRatio: Double
    var swapUsedBytes: UInt64
    var swapGrowthBytes: Int64
    var effectivePressureScore: Double
}

struct DiagnosticsInput {
    var timestamp: Date
    var cpuStats: CPUStats?
    var cpuHistory: [Double]
    var thermalState: ProcessInfo.ThermalState
    var thermalHistory: [ProcessInfo.ThermalState]
    var topCPUProcesses: [RunningProcessStats]
    var topMemoryProcesses: [MemoryProcessStats]
    var memorySignal: DiagnosticsMemorySignal?
    var memorySignalHistory: [DiagnosticsMemorySignal]
    var diskFreeBytes: UInt64
    var diskTotalBytes: UInt64
}
