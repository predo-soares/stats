import Foundation

@main
struct RunCursorImportSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkCoverageAndResume(failures: &failures)
        await checkSplitLeavesCoverageIncomplete(failures: &failures)
        await checkRetentionPrunesCoverage(failures: &failures)
        if failures.isEmpty {
            print("PASS: Cursor import checkpoint and coverage checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkCoverageAndResume(failures: inout [String]) async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stats-cursor-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let ledger = try CodexUsageLedger(directory: directory)
            let first = CursorUsageRange(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
            let second = CursorUsageRange(start: Date(timeIntervalSince1970: 200), end: Date(timeIntervalSince1970: 300))
            try await ledger.seedCursorImportRanges([first, second], workspaceID: "fixture", now: Date(timeIntervalSince1970: 300))
            try await ledger.completeCursorImport(.confirmedEmpty, workspaceID: "fixture", range: first)
            let target = UsageDateRange(start: first.start, end: second.end)
            if try await ledger.cursorCoverage(workspaceID: "fixture", range: target) != .incomplete {
                failures.append("partial confirmed-empty coverage was treated as complete")
            }
            try await ledger.completeCursorImport(.confirmedEmpty, workspaceID: "fixture", range: second)
            if try await ledger.cursorCoverage(workspaceID: "fixture", range: target) != .complete {
                failures.append("adjacent completed ranges did not establish complete coverage")
            }
            let reopened = try CodexUsageLedger(directory: directory)
            if try await reopened.cursorCoverage(workspaceID: "fixture", range: target) != .complete {
                failures.append("completed Cursor coverage did not survive ledger reopen")
            }
        } catch {
            failures.append("coverage checkpoint setup failed: \(error)")
        }
    }

    private static func checkSplitLeavesCoverageIncomplete(failures: inout [String]) async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stats-cursor-split-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let ledger = try CodexUsageLedger(directory: directory)
            let parent = CursorUsageRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 172_800))
            let halves = parent.split()!
            try await ledger.seedCursorImportRanges([parent], workspaceID: "fixture")
            try await ledger.splitCursorImport(parent, workspaceID: "fixture", into: [halves.0, halves.1])
            let target = UsageDateRange(start: parent.start, end: parent.end)
            if try await ledger.cursorCoverage(workspaceID: "fixture", range: target) != .incomplete {
                failures.append("a split parent was treated as imported coverage")
            }
            let next = try await ledger.nextCursorImportRange(workspaceID: "fixture")
            if next?.range != halves.1 {
                failures.append("split range did not enqueue the most recent child for import")
            }
        } catch {
            failures.append("split checkpoint setup failed: \(error)")
        }
    }

    private static func checkRetentionPrunesCoverage(failures: inout [String]) async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "stats-cursor-retention-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let ledger = try CodexUsageLedger(directory: directory)
            let range = CursorUsageRange(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
            try await ledger.seedCursorImportRanges([range], workspaceID: "fixture")
            try await ledger.completeCursorImport(.confirmedEmpty, workspaceID: "fixture", range: range)
            try await ledger.pruneCursorHistory(workspaceID: "fixture", before: Date(timeIntervalSince1970: 21))
            if try await ledger.cursorCoverage(workspaceID: "fixture", range: UsageDateRange(start: range.start, end: range.end)) != .incomplete {
                failures.append("Cursor retention left expired import coverage behind")
            }
        } catch {
            failures.append("retention checkpoint setup failed: \(error)")
        }
    }
}
