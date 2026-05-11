import AppKit
import Foundation

struct DiagnosticsInputMapper {
    func map(
        snapshot: SystemStatsSnapshot,
        cpuHistory: [Double],
        thermalState: ProcessInfo.ThermalState,
        thermalHistory: [ProcessInfo.ThermalState],
        memorySignalHistory: [DiagnosticsMemorySignal]
    ) -> DiagnosticsInput {
        let memorySignal = snapshot.memoryStats.map { stats in
            makeMemorySignal(stats: stats, history: memorySignalHistory, timestamp: snapshot.lastUpdated)
        }

        let freeBytes = snapshot.diskTotal > snapshot.diskUsed ? snapshot.diskTotal - snapshot.diskUsed : 0

        return DiagnosticsInput(
            timestamp: snapshot.lastUpdated,
            cpuStats: snapshot.cpuStats,
            cpuHistory: cpuHistory,
            thermalState: thermalState,
            thermalHistory: thermalHistory,
            topCPUProcesses: snapshot.topProcesses,
            topMemoryProcesses: snapshot.topMemoryProcesses,
            memorySignal: memorySignal,
            memorySignalHistory: memorySignalHistory,
            diskFreeBytes: freeBytes,
            diskTotalBytes: snapshot.diskTotal
        )
    }

    func makeMemorySignal(
        stats: MemoryStats,
        history: [DiagnosticsMemorySignal],
        timestamp: Date
    ) -> DiagnosticsMemorySignal {
        let usageRatio = stats.pressure
        let compressedRatio = stats.total > 0 ? Double(stats.compressed) / Double(stats.total) : 0
        let previousSwap = history.last?.swapUsedBytes ?? stats.swapUsed
        let swapGrowth = Int64(stats.swapUsed) - Int64(previousSwap)
        let swapRatio = stats.total > 0 ? Double(stats.swapUsed) / Double(stats.total) : 0
        let effectivePressure = min(max(max(usageRatio, compressedRatio * 2) + (swapRatio * 4), 0), 1)

        return DiagnosticsMemorySignal(
            timestamp: timestamp,
            usageRatio: usageRatio,
            compressedRatio: compressedRatio,
            swapUsedBytes: stats.swapUsed,
            swapGrowthBytes: swapGrowth,
            effectivePressureScore: effectivePressure
        )
    }
}

struct DiagnosticsEngine {
    func evaluate(input: DiagnosticsInput) -> [DiagnosticsIssueDraft] {
        let signals = [
            cpuSignal(input: input),
            thermalSignal(input: input),
            memorySignal(input: input),
            lowDiskSignal(input: input)
        ].compactMap { $0 }

        return compose(signals: signals, input: input)
    }

    private func compose(signals: [DiagnosticsIssueDraft], input: DiagnosticsInput) -> [DiagnosticsIssueDraft] {
        let grouped = Dictionary(grouping: signals, by: \.type)

        return grouped.values.compactMap { drafts in
            guard let first = drafts.first else { return nil }
            let highestSeverity = drafts.max { $0.severity.sortPriority < $1.severity.sortPriority }?.severity ?? first.severity
            let mergedRules = Array(Set(drafts.flatMap(\.contributingRuleIDs))).sorted { $0.rawValue < $1.rawValue }
            let mergedContributors = drafts.flatMap(\.context.contributors)
            let uniqueContributors = Array(Set(mergedContributors)).prefix(3)

            let action = mergedAction(for: first.type, drafts: drafts, input: input)
            let title = mergedTitle(for: first.type, drafts: drafts)
            let context = DiagnosticsContextSnapshot(
                timestamp: input.timestamp,
                cpuUsage: input.cpuStats?.active,
                thermalState: StatsFormatting.thermalStateString(input.thermalState),
                memoryPressureScore: input.memorySignal?.effectivePressureScore,
                swapUsedBytes: input.memorySignal?.swapUsedBytes,
                diskFreeBytes: input.diskFreeBytes,
                diskFreeRatio: input.diskTotalBytes > 0 ? Double(input.diskFreeBytes) / Double(input.diskTotalBytes) : nil,
                contributors: Array(uniqueContributors)
            )

            return DiagnosticsIssueDraft(
                type: first.type,
                severity: highestSeverity,
                title: title,
                suggestedAction: action,
                contributingRuleIDs: mergedRules,
                context: context
            )
        }
        .sorted { lhs, rhs in
            if lhs.severity.sortPriority != rhs.severity.sortPriority {
                return lhs.severity.sortPriority > rhs.severity.sortPriority
            }

            let lhsActionable = !lhs.suggestedAction.isEmpty
            let rhsActionable = !rhs.suggestedAction.isEmpty
            if lhsActionable != rhsActionable {
                return lhsActionable
            }

            return lhs.type.rawValue < rhs.type.rawValue
        }
    }

    private func mergedTitle(for type: DiagnosticsIssueType, drafts: [DiagnosticsIssueDraft]) -> String {
        switch type {
        case .systemUnderHeavyLoad:
            if drafts.contains(where: { $0.contributingRuleIDs.contains(.thermalStress) }) &&
                drafts.contains(where: { $0.contributingRuleIDs.contains(.cpuSaturation) }) {
                return "System Under Heavy Load"
            }

            if drafts.contains(where: { $0.contributingRuleIDs.contains(.thermalStress) }) {
                return "Thermal Stress"
            }

            return "Sustained CPU Load"
        case .memoryPressure:
            return "Memory Pressure"
        case .lowDiskSpace:
            return "Low Disk Space"
        }
    }

    private func mergedAction(
        for type: DiagnosticsIssueType,
        drafts: [DiagnosticsIssueDraft],
        input: DiagnosticsInput
    ) -> String {
        switch type {
        case .systemUnderHeavyLoad:
            return recommendedCPUAction(for: input.topCPUProcesses)
        case .memoryPressure:
            if let offender = input.topMemoryProcesses.first {
                return "Close high-memory apps first, starting with \(offender.name), if you need memory back quickly."
            }
            return "Close a few memory-heavy apps to reduce pressure and swap use."
        case .lowDiskSpace:
            return "Free disk space by removing large files or unused apps before storage pressure gets worse."
        }
    }

    private func cpuSignal(input: DiagnosticsInput) -> DiagnosticsIssueDraft? {
        let window = Array(input.cpuHistory.suffix(15))
        guard window.count >= 10 else { return nil }

        let sustainedCount = window.filter { $0 >= 0.75 }.count
        guard sustainedCount >= 10 else { return nil }

        let average = window.reduce(0, +) / Double(window.count)
        guard average >= 0.75 else { return nil }

        let severity: DiagnosticsIssueSeverity = average >= 0.9 && sustainedCount >= 12 ? .critical : .warning
        let contributors = topCPUContributors(from: input.topCPUProcesses)

        return DiagnosticsIssueDraft(
            type: .systemUnderHeavyLoad,
            severity: severity,
            title: "Sustained CPU Load",
            suggestedAction: recommendedCPUAction(for: input.topCPUProcesses),
            contributingRuleIDs: [.cpuSaturation],
            context: DiagnosticsContextSnapshot(
                timestamp: input.timestamp,
                cpuUsage: input.cpuStats?.active,
                thermalState: StatsFormatting.thermalStateString(input.thermalState),
                memoryPressureScore: input.memorySignal?.effectivePressureScore,
                swapUsedBytes: input.memorySignal?.swapUsedBytes,
                diskFreeBytes: input.diskFreeBytes,
                diskFreeRatio: input.diskTotalBytes > 0 ? Double(input.diskFreeBytes) / Double(input.diskTotalBytes) : nil,
                contributors: contributors
            )
        )
    }

    private func thermalSignal(input: DiagnosticsInput) -> DiagnosticsIssueDraft? {
        let window = Array(input.thermalHistory.suffix(6))
        guard !window.isEmpty else { return nil }

        let nonNominalCount = window.filter { $0 != .nominal }.count
        guard nonNominalCount >= 3 else { return nil }

        let severity: DiagnosticsIssueSeverity = input.thermalState == .serious || input.thermalState == .critical ? .critical : .warning
        return DiagnosticsIssueDraft(
            type: .systemUnderHeavyLoad,
            severity: severity,
            title: "Thermal Stress",
            suggestedAction: recommendedCPUAction(for: input.topCPUProcesses),
            contributingRuleIDs: [.thermalStress],
            context: DiagnosticsContextSnapshot(
                timestamp: input.timestamp,
                cpuUsage: input.cpuStats?.active,
                thermalState: StatsFormatting.thermalStateString(input.thermalState),
                memoryPressureScore: input.memorySignal?.effectivePressureScore,
                swapUsedBytes: input.memorySignal?.swapUsedBytes,
                diskFreeBytes: input.diskFreeBytes,
                diskFreeRatio: input.diskTotalBytes > 0 ? Double(input.diskFreeBytes) / Double(input.diskTotalBytes) : nil,
                contributors: topCPUContributors(from: input.topCPUProcesses)
            )
        )
    }

    private func memorySignal(input: DiagnosticsInput) -> DiagnosticsIssueDraft? {
        guard let signal = input.memorySignal else { return nil }

        let recent = Array(input.memorySignalHistory.suffix(3))
        let sustainedPressure = recent.filter { $0.effectivePressureScore >= 0.78 }.count >= 2 || signal.effectivePressureScore >= 0.85
        let swapActive = signal.swapUsedBytes >= 512 * 1_024 * 1_024 || signal.swapGrowthBytes >= 128 * 1_024 * 1_024
        guard sustainedPressure && swapActive else { return nil }

        let severity: DiagnosticsIssueSeverity =
            signal.effectivePressureScore >= 0.92 || signal.swapUsedBytes >= 2 * 1_024 * 1_024 * 1_024
            ? .critical
            : .warning

        let contributors = input.topMemoryProcesses.prefix(3).map {
            DiagnosticsIssueContributor(
                name: $0.name,
                detail: StatsFormatting.byteString($0.memoryBytes)
            )
        }

        return DiagnosticsIssueDraft(
            type: .memoryPressure,
            severity: severity,
            title: "Memory Pressure",
            suggestedAction: mergedAction(for: .memoryPressure, drafts: [], input: input),
            contributingRuleIDs: signal.swapGrowthBytes > 0 ? [.memoryStress, .swapGrowth] : [.memoryStress],
            context: DiagnosticsContextSnapshot(
                timestamp: input.timestamp,
                cpuUsage: input.cpuStats?.active,
                thermalState: StatsFormatting.thermalStateString(input.thermalState),
                memoryPressureScore: signal.effectivePressureScore,
                swapUsedBytes: signal.swapUsedBytes,
                diskFreeBytes: input.diskFreeBytes,
                diskFreeRatio: input.diskTotalBytes > 0 ? Double(input.diskFreeBytes) / Double(input.diskTotalBytes) : nil,
                contributors: contributors
            )
        )
    }

    private func lowDiskSignal(input: DiagnosticsInput) -> DiagnosticsIssueDraft? {
        guard input.diskTotalBytes > 0 else { return nil }

        let freeRatio = Double(input.diskFreeBytes) / Double(input.diskTotalBytes)
        let warning = freeRatio < 0.15 || input.diskFreeBytes < 50 * 1_024 * 1_024 * 1_024
        guard warning else { return nil }

        let severity: DiagnosticsIssueSeverity =
            freeRatio < 0.08 || input.diskFreeBytes < 20 * 1_024 * 1_024 * 1_024
            ? .critical
            : .warning

        return DiagnosticsIssueDraft(
            type: .lowDiskSpace,
            severity: severity,
            title: "Low Disk Space",
            suggestedAction: mergedAction(for: .lowDiskSpace, drafts: [], input: input),
            contributingRuleIDs: [.lowDisk],
            context: DiagnosticsContextSnapshot(
                timestamp: input.timestamp,
                cpuUsage: input.cpuStats?.active,
                thermalState: StatsFormatting.thermalStateString(input.thermalState),
                memoryPressureScore: input.memorySignal?.effectivePressureScore,
                swapUsedBytes: input.memorySignal?.swapUsedBytes,
                diskFreeBytes: input.diskFreeBytes,
                diskFreeRatio: freeRatio,
                contributors: []
            )
        )
    }

    private func topCPUContributors(from processes: [RunningProcessStats]) -> [DiagnosticsIssueContributor] {
        Array(processes.prefix(3)).map {
            DiagnosticsIssueContributor(
                name: $0.name,
                detail: StatsFormatting.processPercentString($0.cpuPercent)
            )
        }
    }

    private func recommendedCPUAction(for processes: [RunningProcessStats]) -> String {
        let classification = classifyProcesses(processes)

        switch classification {
        case .foregroundApp:
            if let process = processes.first {
                return "Quit or restart \(process.name) if it stays unresponsive or keeps driving sustained load."
            }
            return "Close a busy foreground app if load stays high."
        case .mixedWorkload:
            return "Reduce concurrent heavy apps or workflows for a few minutes to bring CPU load back down."
        case .backgroundSystem:
            return "Let background work finish, or restart the Mac later if system load keeps staying high."
        }
    }

    private func classifyProcesses(_ processes: [RunningProcessStats]) -> DiagnosticsProcessClass {
        guard let top = processes.first else { return .mixedWorkload }
        let total = processes.prefix(3).reduce(0) { $0 + $1.cpuPercent }
        let topShare = total > 0 ? top.cpuPercent / total : 0

        let appLikeCount = processes.prefix(3).filter { process in
            if NSRunningApplication(processIdentifier: process.pid) != nil {
                return true
            }

            let lowercase = process.name.lowercased()
            return !lowercase.hasPrefix("md") &&
                !lowercase.hasSuffix("d") &&
                !lowercase.contains("helper")
        }.count

        if topShare >= 0.6, appLikeCount > 0 {
            return .foregroundApp
        }

        if appLikeCount == 0 {
            return .backgroundSystem
        }

        return .mixedWorkload
    }
}
