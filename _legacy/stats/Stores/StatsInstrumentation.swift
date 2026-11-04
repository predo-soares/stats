import Foundation
import os

struct InstrumentationDurationSnapshot {
    let samples: Int
    let lastMS: Double
    let averageMS: Double
    let maxMS: Double
}

struct InstrumentationCycleSnapshot {
    let runs: Int
    let overlaps: Int
    let delayedRuns: Int
    let estimatedSkippedRuns: Int
    let lastDurationMS: Double
    let averageDurationMS: Double
    let maxDurationMS: Double
    let lastDelayMS: Double
    let maxDelayMS: Double
}

struct ProcessEnumerationSnapshot {
    let samples: Int
    let lastDurationMS: Double
    let averageDurationMS: Double
    let maxDurationMS: Double
    let lastProcessCount: Int
    let averageProcessCount: Double
    let maxProcessCount: Int
    let lastPIDInfoCalls: Int
}

struct SystemStatsInstrumentationSnapshot {
    let subsystemDurations: [String: InstrumentationDurationSnapshot]
    let cycleStats: [String: InstrumentationCycleSnapshot]
    let processEnumeration: ProcessEnumerationSnapshot
}

final class SystemStatsInstrumentation {
    enum Metric: String, CaseIterable {
        case hardwareInfo = "hardware_info"
        case memorySample = "memory_sample"
        case diskSample = "disk_sample"
        case networkSample = "network_sample"
        case batterySample = "battery_sample"
        case topMemoryProcesses = "top_memory_processes"
        case cpuTicks = "cpu_ticks"
        case topCPUProcesses = "top_cpu_processes"
        case cpuTemperature = "cpu_temperature"
        case gpuSample = "gpu_sample"
        case refreshPublish = "refresh_publish"
        case cpuPublish = "cpu_publish"
        case mainPanelPresentation = "panel_main_presentation"
        case cpuPanelPresentation = "panel_cpu_presentation"
        case memoryPanelPresentation = "panel_memory_presentation"
        case diskPanelPresentation = "panel_disk_presentation"
    }

    enum Cycle: String, CaseIterable {
        case refreshTimer = "refresh_timer"
        case memoryTimer = "memory_timer"
        case cpuTimer = "cpu_timer"
        case manualRefresh = "manual_refresh"
    }

    struct CycleToken {
        let cycle: Cycle
        let startedAt: UInt64
    }

    private struct DurationTracker {
        var samples = 0
        var totalMS = 0.0
        var lastMS = 0.0
        var maxMS = 0.0

        mutating func record(_ elapsedMS: Double) {
            samples += 1
            totalMS += elapsedMS
            lastMS = elapsedMS
            maxMS = max(maxMS, elapsedMS)
        }

        var snapshot: InstrumentationDurationSnapshot {
            InstrumentationDurationSnapshot(
                samples: samples,
                lastMS: lastMS,
                averageMS: samples > 0 ? totalMS / Double(samples) : 0,
                maxMS: maxMS
            )
        }
    }

    private struct CycleTracker {
        var runs = 0
        var overlaps = 0
        var delayedRuns = 0
        var estimatedSkippedRuns = 0
        var isActive = false
        var lastStartTime: UInt64?
        var lastDurationMS = 0.0
        var totalDurationMS = 0.0
        var maxDurationMS = 0.0
        var lastDelayMS = 0.0
        var maxDelayMS = 0.0

        mutating func begin(now: UInt64, expectedInterval: TimeInterval?) {
            if isActive {
                overlaps += 1
            }

            if let expectedInterval, let lastStartTime {
                let actualInterval = Double(now - lastStartTime) / 1_000_000_000
                let delayMS = max((actualInterval - expectedInterval) * 1_000, 0)
                lastDelayMS = delayMS
                maxDelayMS = max(maxDelayMS, delayMS)

                if actualInterval > (expectedInterval * 1.2) {
                    delayedRuns += 1
                }

                if expectedInterval > 0 {
                    estimatedSkippedRuns += max(Int(actualInterval / expectedInterval) - 1, 0)
                }
            } else {
                lastDelayMS = 0
            }

            isActive = true
            lastStartTime = now
        }

        mutating func end(durationMS: Double) {
            runs += 1
            totalDurationMS += durationMS
            lastDurationMS = durationMS
            maxDurationMS = max(maxDurationMS, durationMS)
            isActive = false
        }

        var snapshot: InstrumentationCycleSnapshot {
            InstrumentationCycleSnapshot(
                runs: runs,
                overlaps: overlaps,
                delayedRuns: delayedRuns,
                estimatedSkippedRuns: estimatedSkippedRuns,
                lastDurationMS: lastDurationMS,
                averageDurationMS: runs > 0 ? totalDurationMS / Double(runs) : 0,
                maxDurationMS: maxDurationMS,
                lastDelayMS: lastDelayMS,
                maxDelayMS: maxDelayMS
            )
        }
    }

    private struct ProcessEnumerationTracker {
        var samples = 0
        var totalDurationMS = 0.0
        var lastDurationMS = 0.0
        var maxDurationMS = 0.0
        var totalProcessCount = 0
        var lastProcessCount = 0
        var maxProcessCount = 0
        var lastPIDInfoCalls = 0

        mutating func record(durationMS: Double, processCount: Int, pidInfoCalls: Int) {
            samples += 1
            totalDurationMS += durationMS
            lastDurationMS = durationMS
            maxDurationMS = max(maxDurationMS, durationMS)
            totalProcessCount += processCount
            lastProcessCount = processCount
            maxProcessCount = max(maxProcessCount, processCount)
            lastPIDInfoCalls = pidInfoCalls
        }

        var snapshot: ProcessEnumerationSnapshot {
            ProcessEnumerationSnapshot(
                samples: samples,
                lastDurationMS: lastDurationMS,
                averageDurationMS: samples > 0 ? totalDurationMS / Double(samples) : 0,
                maxDurationMS: maxDurationMS,
                lastProcessCount: lastProcessCount,
                averageProcessCount: samples > 0 ? Double(totalProcessCount) / Double(samples) : 0,
                maxProcessCount: maxProcessCount,
                lastPIDInfoCalls: lastPIDInfoCalls
            )
        }
    }

    private let logger = Logger(subsystem: "aestech.stats", category: "instrumentation")
    private let debugLoggingEnabled = ProcessInfo.processInfo.environment["STATS_DEBUG_INSTRUMENTATION"] == "1"

    private var durationTrackers: [Metric: DurationTracker] = [:]
    private var cycleTrackers: [Cycle: CycleTracker] = [:]
    private var processEnumerationTracker = ProcessEnumerationTracker()

    func measure<T>(_ metric: Metric, _ work: () -> T) -> T {
        let startedAt = now()
        let result = work()
        record(metric, elapsedMS: elapsedMS(since: startedAt))
        return result
    }

    func beginCycle(_ cycle: Cycle, expectedInterval: TimeInterval?) -> CycleToken {
        let startedAt = now()
        var tracker = cycleTrackers[cycle, default: CycleTracker()]
        tracker.begin(now: startedAt, expectedInterval: expectedInterval)
        cycleTrackers[cycle] = tracker
        return CycleToken(cycle: cycle, startedAt: startedAt)
    }

    func endCycle(_ token: CycleToken) {
        var tracker = cycleTrackers[token.cycle, default: CycleTracker()]
        tracker.end(durationMS: elapsedMS(since: token.startedAt))
        cycleTrackers[token.cycle] = tracker
    }

    func record(_ metric: Metric, elapsedMS: Double) {
        var tracker = durationTrackers[metric, default: DurationTracker()]
        tracker.record(elapsedMS)
        durationTrackers[metric] = tracker
    }

    func recordProcessEnumeration(durationMS: Double, processCount: Int, pidInfoCalls: Int) {
        processEnumerationTracker.record(
            durationMS: durationMS,
            processCount: processCount,
            pidInfoCalls: pidInfoCalls
        )
    }

    func formattedReport() -> String {
        let snapshot = snapshot
        let durationLines = Metric.allCases.compactMap { metric -> String? in
            guard let stats = snapshot.subsystemDurations[metric.rawValue], stats.samples > 0 else { return nil }
            return "\(metric.rawValue): last \(formatMS(stats.lastMS)) avg \(formatMS(stats.averageMS)) max \(formatMS(stats.maxMS)) n=\(stats.samples)"
        }

        let cycleLines = Cycle.allCases.compactMap { cycle -> String? in
            guard let stats = snapshot.cycleStats[cycle.rawValue], stats.runs > 0 else { return nil }
            return "\(cycle.rawValue): last \(formatMS(stats.lastDurationMS)) avg \(formatMS(stats.averageDurationMS)) max \(formatMS(stats.maxDurationMS)) overlaps \(stats.overlaps) delayed \(stats.delayedRuns) skipped \(stats.estimatedSkippedRuns)"
        }

        let process = snapshot.processEnumeration
        let processLine = process.samples > 0
            ? "process_enumeration: last \(formatMS(process.lastDurationMS)) avg \(formatMS(process.averageDurationMS)) max \(formatMS(process.maxDurationMS)) procs \(process.lastProcessCount) pidinfo \(process.lastPIDInfoCalls)"
            : "process_enumeration: no samples"

        return ([processLine] + durationLines + cycleLines).joined(separator: "\n")
    }

    func logSummary(reason: String) {
        guard debugLoggingEnabled else { return }
        logger.debug("Instrumentation summary (\(reason, privacy: .public))\n\(self.formattedReport(), privacy: .public)")
    }

    var snapshot: SystemStatsInstrumentationSnapshot {
        SystemStatsInstrumentationSnapshot(
            subsystemDurations: durationTrackers.reduce(into: [:]) { result, entry in
                result[entry.key.rawValue] = entry.value.snapshot
            },
            cycleStats: cycleTrackers.reduce(into: [:]) { result, entry in
                result[entry.key.rawValue] = entry.value.snapshot
            },
            processEnumeration: processEnumerationTracker.snapshot
        )
    }

    private func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private func elapsedMS(since startedAt: UInt64) -> Double {
        Double(now() - startedAt) / 1_000_000
    }

    private func formatMS(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2))))ms"
    }
}
