import Foundation

@main
struct RunCodexUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkInclusiveCachedInputAndTodayProjection(failures: &failures)
        await checkRepeatedImportDoesNotInflate(failures: &failures)
        await checkMissingSessionsStayEmpty(failures: &failures)
        await checkCumulativeTotalSnapshotIsIgnored(failures: &failures)

        if failures.isEmpty {
            print("PASS: Codex source-to-ledger Today checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkInclusiveCachedInputAndTodayProjection(failures: inout [String]) async {
        let root = temporaryRoot("codex-normalize")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions")
        let ledgerDir = root.appending(path: "ledger")
        let now = Date(timeIntervalSince1970: 1_700_000_800)
        try! writeSession(
            at: sessions.appending(path: "rollout.jsonl"),
            lines: [
                tokenCountLine(timestamp: "2023-11-14T22:00:00Z", inclusiveInput: 15, cached: 5, output: 2, model: "gpt-a"),
                tokenCountLine(timestamp: "2023-11-14T22:10:00Z", inclusiveInput: 10, cached: 0, output: 3, model: "gpt-a")
            ]
        )
        do {
            let ledger = try CodexUsageLedger(directory: ledgerDir)
            let importer = CodexUsageImporter(sessionsURL: sessions)
            let projection = try await importer.importAvailableSessions(into: ledger)
            let today = try await ledger.today(now: now, calendar: utcCalendar)
            // Inclusive input 15 with cached 5 → 10 non-cache + 5 cached; second event 10 + 0 cached + 3 output.
            guard today.inputTokens == 20, today.cachedInputTokens == 5, today.outputTokens == 5, today.totalTokens == 30, today.records == 2 else {
                failures.append("Today projection did not normalize inclusive cached input (\(today.inputTokens)/\(today.cachedInputTokens)/\(today.outputTokens)/\(today.records))")
                return
            }
            guard case .available = today.coverage, today.cutoff != nil else {
                failures.append("Today projection did not publish local-device coverage and cutoff")
                return
            }
            // Importer returns wall-clock today; fixtures are fixed — only assert ledger query above for tokens.
            _ = projection
        } catch {
            failures.append("normalize/import failed: \(error)")
        }
    }

    private static func checkRepeatedImportDoesNotInflate(failures: inout [String]) async {
        let root = temporaryRoot("codex-reimport")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions")
        let ledgerDir = root.appending(path: "ledger")
        let now = Date(timeIntervalSince1970: 1_700_000_800)
        try! writeSession(
            at: sessions.appending(path: "nested/day/rollout.jsonl"),
            lines: [
                tokenCountLine(timestamp: "2023-11-14T21:00:00Z", inclusiveInput: 8, cached: 2, output: 1, model: "gpt-b")
            ]
        )
        do {
            let ledger = try CodexUsageLedger(directory: ledgerDir)
            let importer = CodexUsageImporter(sessionsURL: sessions)
            _ = try await importer.importAvailableSessions(into: ledger)
            let first = try await ledger.today(now: now, calendar: utcCalendar)
            _ = try await importer.importAvailableSessions(into: ledger)
            let second = try await ledger.today(now: now, calendar: utcCalendar)
            guard first.totalTokens == second.totalTokens, first.records == second.records, first.records == 1, first.totalTokens == 9 else {
                failures.append("repeated import inflated or lost Codex Today totals")
                return
            }
        } catch {
            failures.append("reimport check failed: \(error)")
        }
    }

    private static func checkMissingSessionsStayEmpty(failures: inout [String]) async {
        let root = temporaryRoot("codex-missing")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let ledger = try CodexUsageLedger(directory: root.appending(path: "ledger"))
            let importer = CodexUsageImporter(sessionsURL: root.appending(path: "missing-sessions"))
            let projection = try await importer.importAvailableSessions(into: ledger)
            guard projection.records == 0, projection.totalTokens == 0, case .empty = projection.coverage else {
                failures.append("missing sessions directory was not treated as empty local coverage")
                return
            }
        } catch {
            failures.append("missing sessions check failed: \(error)")
        }
    }

    private static func checkCumulativeTotalSnapshotIsIgnored(failures: inout [String]) async {
        let root = temporaryRoot("codex-ignore-total")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions")
        let now = Date(timeIntervalSince1970: 1_700_000_800)
        let cumulativeOnly = #"{"type":"event_msg","timestamp":"2023-11-14T22:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999,"cached_input_tokens":100,"output_tokens":50}},"model":"gpt-a"}}"#
        try! writeSession(at: sessions.appending(path: "rollout.jsonl"), lines: [cumulativeOnly])
        do {
            let ledger = try CodexUsageLedger(directory: root.appending(path: "ledger"))
            let importer = CodexUsageImporter(sessionsURL: sessions)
            _ = try await importer.importAvailableSessions(into: ledger)
            let today = try await ledger.today(now: now, calendar: utcCalendar)
            guard today.records == 0, today.totalTokens == 0 else {
                failures.append("cumulative total_token_usage snapshot was counted as consumption")
                return
            }
        } catch {
            failures.append("total_token_usage ignore check failed: \(error)")
        }
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stats-\(name)-\(UUID().uuidString)")
    }

    private static func writeSession(at url: URL, lines: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func tokenCountLine(timestamp: String, inclusiveInput: Int, cached: Int, output: Int, model: String) -> String {
        #"{"type":"event_msg","timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(inclusiveInput),"cached_input_tokens":\#(cached),"output_tokens":\#(output)}},"model":"\#(model)"}}"#
    }
}
