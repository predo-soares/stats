import Foundation

struct DiagnosticsSelfCheckReport {
    var passedChecks: [String]
    var failedChecks: [String]

    var isSuccessful: Bool {
        failedChecks.isEmpty
    }

    var summary: String {
        let status = isSuccessful ? "PASS" : "FAIL"
        let passed = passedChecks.count
        let failed = failedChecks.count
        return "\(status) diagnostics self-checks (\(passed) passed, \(failed) failed)"
    }
}

struct DiagnosticsSelfChecks {
    func run() async -> DiagnosticsSelfCheckReport {
        var passed: [String] = []
        var failed: [String] = []

        await record("cpu rule ignores brief spike", passed: &passed, failed: &failed) {
            let engine = DiagnosticsEngine()
            let input = makeCPUInput(history: [0.92], topProcesses: [RunningProcessStats(pid: 100, name: "Xcode", cpuPercent: 82)])
            return engine.evaluate(input: input).isEmpty
        }

        await record("cpu rule opens after sustained load", passed: &passed, failed: &failed) {
            let engine = DiagnosticsEngine()
            let input = makeCPUInput(
                history: Array(repeating: 0.88, count: 15),
                topProcesses: [RunningProcessStats(pid: 101, name: "Xcode", cpuPercent: 87)]
            )
            let drafts = engine.evaluate(input: input)
            return drafts.contains { draft in
                draft.type == .systemUnderHeavyLoad &&
                draft.contributingRuleIDs.contains(.cpuSaturation)
            }
        }

        await record("memory rule requires pressure and swap", passed: &passed, failed: &failed) {
            let engine = DiagnosticsEngine()
            let now = Date()
            let signal = DiagnosticsMemorySignal(
                timestamp: now,
                usageRatio: 0.82,
                compressedRatio: 0.12,
                swapUsedBytes: 1_400_000_000,
                swapGrowthBytes: 256_000_000,
                effectivePressureScore: 0.88
            )
            let input = DiagnosticsInput(
                timestamp: now,
                cpuStats: CPUStats(user: 0.15, system: 0.2, idle: 0.65),
                cpuHistory: [],
                thermalState: .nominal,
                thermalHistory: [],
                topCPUProcesses: [],
                topMemoryProcesses: [MemoryProcessStats(pid: 102, name: "Chrome", memoryBytes: 2_500_000_000)],
                memorySignal: signal,
                memorySignalHistory: [signal, signal, signal],
                diskFreeBytes: 200_000_000_000,
                diskTotalBytes: 500_000_000_000
            )
            return engine.evaluate(input: input).contains { $0.type == .memoryPressure }
        }

        await record("event tracker opens, updates, and resolves one issue", passed: &passed, failed: &failed) {
            var tracker = DiagnosticsEventTracker()
            let now = Date()
            let draft = makeDraft(type: .systemUnderHeavyLoad, at: now)

            let opened = tracker.apply(drafts: [draft], at: now)
            guard opened.activeIssues.count == 1, opened.recentResolvedIssues.isEmpty else {
                return false
            }

            let updated = tracker.apply(drafts: [draft], at: now.addingTimeInterval(15))
            guard updated.activeIssues.count == 1, updated.recentResolvedIssues.isEmpty else {
                return false
            }

            let resolved = tracker.apply(drafts: [], at: now.addingTimeInterval(30))
            guard resolved.activeIssues.isEmpty, resolved.recentResolvedIssues.count == 1 else {
                return false
            }

            return resolved.recentResolvedIssues[0].resolvedAt != nil
        }

        await record("persistence round-trip preserves lifecycle state", passed: &passed, failed: &failed) {
            let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let persistence = DiagnosticsPersistence(baseDirectoryURL: tempDirectory)
            let now = Date()
            let activeEvent = makeEvent(type: .systemUnderHeavyLoad, status: .active, openedAt: now, resolvedAt: nil)
            let resolvedEvent = makeEvent(
                type: .memoryPressure,
                status: .resolved,
                openedAt: now.addingTimeInterval(-120),
                resolvedAt: now
            )

            await persistence.save(active: [activeEvent], resolved: [resolvedEvent])
            let loaded = await persistence.load()
            let roundTripOK = loaded.active == [activeEvent] && loaded.resolved == [resolvedEvent]

            await persistence.clear()
            let cleared = await persistence.load()

            return roundTripOK && cleared.active.isEmpty && cleared.resolved.isEmpty
        }

        return DiagnosticsSelfCheckReport(passedChecks: passed, failedChecks: failed)
    }

    private func record(
        _ name: String,
        passed: inout [String],
        failed: inout [String],
        check: () async -> Bool
    ) async {
        if await check() {
            passed.append(name)
        } else {
            failed.append(name)
        }
    }

    private func makeCPUInput(history: [Double], topProcesses: [RunningProcessStats]) -> DiagnosticsInput {
        let now = Date()
        return DiagnosticsInput(
            timestamp: now,
            cpuStats: CPUStats(user: 0.5, system: 0.38, idle: 0.12),
            cpuHistory: history,
            thermalState: .nominal,
            thermalHistory: Array(repeating: .nominal, count: 3),
            topCPUProcesses: topProcesses,
            topMemoryProcesses: [],
            memorySignal: nil,
            memorySignalHistory: [],
            diskFreeBytes: 300_000_000_000,
            diskTotalBytes: 500_000_000_000
        )
    }

    private func makeDraft(type: DiagnosticsIssueType, at timestamp: Date) -> DiagnosticsIssueDraft {
        DiagnosticsIssueDraft(
            type: type,
            severity: .warning,
            title: type.title,
            suggestedAction: "Action",
            contributingRuleIDs: [.cpuSaturation],
            context: DiagnosticsContextSnapshot(
                timestamp: timestamp,
                cpuUsage: 0.82,
                thermalState: "Fair",
                memoryPressureScore: nil,
                swapUsedBytes: nil,
                diskFreeBytes: 250_000_000_000,
                diskFreeRatio: 0.5,
                contributors: [DiagnosticsIssueContributor(name: "Xcode", detail: "81%")]
            )
        )
    }

    private func makeEvent(
        type: DiagnosticsIssueType,
        status: DiagnosticsIssueStatus,
        openedAt: Date,
        resolvedAt: Date?
    ) -> DiagnosticsIssueEvent {
        DiagnosticsIssueEvent(
            id: UUID().uuidString,
            type: type,
            status: status,
            severity: .warning,
            title: type.title,
            suggestedAction: "Action",
            contributingRuleIDs: [.cpuSaturation],
            openedAt: openedAt,
            lastSeenAt: resolvedAt ?? openedAt,
            resolvedAt: resolvedAt,
            context: DiagnosticsContextSnapshot(
                timestamp: openedAt,
                cpuUsage: 0.8,
                thermalState: "Fair",
                memoryPressureScore: nil,
                swapUsedBytes: nil,
                diskFreeBytes: 220_000_000_000,
                diskFreeRatio: 0.44,
                contributors: []
            )
        )
    }
}
