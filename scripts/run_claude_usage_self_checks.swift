import Foundation

@main
struct RunClaudeUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkFixtureTotals(failures: &failures)
        await checkPrivacyShape(failures: &failures)
        await checkUnknownModelCostIncomplete(failures: &failures)
        await checkFailureIsolationPreservesLedger(failures: &failures)

        if failures.isEmpty {
            print("PASS: Claude fixture-to-ledger checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkFixtureTotals(failures: inout [String]) async {
        let root = temporaryRoot("claude-fixture")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appending(path: "projects")
        let ledgerDir = root.appending(path: "ledger")
        let fixture = fixtureURL()
        do {
            try FileManager.default.createDirectory(at: projects.appending(path: "sess"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture, to: projects.appending(path: "sess/claude-session.fixture.jsonl"))
            let importer = ClaudeUsageImporter(projectsURL: projects)
            let events = try importer.importEvents()
            guard events.count == 3 else {
                failures.append("expected 3 deduped events, got \(events.count)")
                return
            }
            let ledger = try CodexUsageLedger(directory: ledgerDir)
            try await ledger.replaceLocal(provider: .claude, events: events)
            let now = fixtureObservationInstant
            let calendar = utcCalendar
            let allTime = try await ledger.local(
                provider: .claude,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: now.addingTimeInterval(86400))
            )
            guard allTime.inputTokens == 2470,
                  allTime.cachedInputTokens == 12096,
                  allTime.cacheCreationTokens == 512,
                  allTime.outputTokens == 556,
                  allTime.reasoningTokens == 0,
                  allTime.totalTokens == 15634,
                  allTime.records == 3
            else {
                failures.append("fixture totals mismatch (\(allTime.inputTokens)/\(allTime.cachedInputTokens)/\(allTime.cacheCreationTokens)/\(allTime.outputTokens)/\(allTime.totalTokens)/\(allTime.records))")
                return
            }
            let today = try await ledger.localToday(provider: .claude, now: now, calendar: calendar)
            guard today.totalTokens == 15634, today.records == 3 else {
                failures.append("today projection did not include fixture day (\(today.totalTokens)/\(today.records))")
                return
            }
        } catch {
            failures.append("fixture import/ledger failed: \(error)")
        }
    }

    private static func checkPrivacyShape(failures: inout [String]) async {
        let event = LocalUsageEvent(
            id: "msg:req",
            providerKind: .claude,
            timestamp: .now,
            model: "claude-sonnet-4-20250514",
            underlyingProvider: nil,
            inputTokens: 1,
            cachedInputTokens: 0,
            cacheCreationTokens: 0,
            outputTokens: 1,
            reasoningTokens: 0
        )
        let labels = Mirror(reflecting: event).children.compactMap { $0.label?.lowercased() }
        let forbidden = ["prompt", "content", "message", "path", "credential", "response", "tool"]
        if let leak = labels.first(where: { label in forbidden.contains(where: { label.contains($0) }) }) {
            failures.append("LocalUsageEvent mirror exposes forbidden field \(leak)")
        }
    }

    private static func checkUnknownModelCostIncomplete(failures: inout [String]) async {
        let catalog = PricingCatalog(revision: "empty", rates: [:])
        let costing = UsageCosting(catalog: catalog)
        let result = costing.estimate([
            PricingTokenUsage(
                model: "claude-unpriced-fixture-model",
                inputTokens: 500,
                cacheReadTokens: 100,
                cacheWriteTokens: 50,
                outputTokens: 25
            )
        ])
        guard result.usageRecords == 1, result.estimate.unpricedTokens == 675, !result.isComplete else {
            failures.append("unknown Claude model should stay unpriced while preserving tokens")
            return
        }
    }

    private static func checkFailureIsolationPreservesLedger(failures: inout [String]) async {
        let root = temporaryRoot("claude-preserve")
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appending(path: "projects")
        let missing = root.appending(path: "missing-projects")
        let ledgerDir = root.appending(path: "ledger")
        do {
            try FileManager.default.createDirectory(at: projects.appending(path: "sess"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: fixtureURL(),
                to: projects.appending(path: "sess/claude-session.fixture.jsonl")
            )
            let ledger = try CodexUsageLedger(directory: ledgerDir)
            let service = ClaudeUsageService(importer: ClaudeUsageImporter(projectsURL: projects))
            _ = try await service.refresh(into: ledger)
            let before = try await ledger.localToday(provider: .claude, now: fixtureObservationInstant, calendar: utcCalendar)
            let failing = ClaudeUsageService(importer: ClaudeUsageImporter(projectsURL: missing))
            let afterFailure = try await failing.refresh(into: ledger, preserveOnFailure: true, now: fixtureObservationInstant, calendar: utcCalendar)
            guard before.totalTokens == afterFailure.projection.totalTokens,
                  before.records == afterFailure.projection.records,
                  afterFailure.projection.records == 3
            else {
                failures.append("missing source cleared or changed retained Claude ledger rows")
                return
            }
            guard case .unavailable = afterFailure.projection.coverage else {
                failures.append("missing source should surface unavailable coverage while preserving tokens")
                return
            }
        } catch {
            failures.append("preserve-on-failure check failed: \(error)")
        }
    }

    private static var fixtureObservationInstant: Date {
        var components = DateComponents()
        components.calendar = utcCalendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 11
        components.day = 1
        components.hour = 23
        return components.date!
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func fixtureURL() -> URL {
        let candidates = [
            URL(fileURLWithPath: "stats/Features/Usage/Fixtures/claude-session.fixture.jsonl"),
            URL(fileURLWithPath: "../stats/Features/Usage/Fixtures/claude-session.fixture.jsonl")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        fatalError("claude-session.fixture.jsonl not found")
    }

    private static func temporaryRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stats-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
