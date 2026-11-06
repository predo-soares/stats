import Foundation

@main
struct RunPiUsageSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkFixtureTotalsAndProvenance(failures: &failures)
        await checkPrivacyIgnoresCwd(failures: &failures)
        await checkUnknownModelCostIncomplete(failures: &failures)
        await checkRetentionPrune(failures: &failures)

        if failures.isEmpty {
            print("PASS: Pi fixture-to-ledger checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkFixtureTotalsAndProvenance(failures: inout [String]) async {
        let root = temporaryRoot("pi-fixture")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions")
        let ledgerDir = root.appending(path: "ledger")
        do {
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixtureURL(), to: sessions.appending(path: "pi-session.fixture.jsonl"))
            let importer = PiUsageImporter(sessionsURL: sessions)
            let events = try importer.importEvents()
            guard events.count == 2 else {
                failures.append("expected 2 Pi events with tokens, got \(events.count)")
                return
            }
            let providers = Set(events.compactMap(\.underlyingProvider))
            guard providers == Set(["anthropic", "openai"]) else {
                failures.append("missing underlying provider provenance \(providers)")
                return
            }
            let ledger = try CodexUsageLedger(directory: ledgerDir)
            try await ledger.replaceLocal(provider: .pi, events: events)
            let allTime = try await ledger.local(
                provider: .pi,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000))
            )
            guard allTime.totalTokens == 3770, allTime.records == 2 else {
                failures.append("Pi fixture totals mismatch (\(allTime.totalTokens)/\(allTime.records))")
                return
            }
            // Pi must not appear under Claude ledger rows.
            let claude = try await ledger.local(
                provider: .claude,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000))
            )
            guard claude.records == 0, claude.totalTokens == 0 else {
                failures.append("Pi events leaked into Claude provider partition")
                return
            }
        } catch {
            failures.append("Pi fixture import failed: \(error)")
        }
    }

    private static func checkPrivacyIgnoresCwd(failures: inout [String]) async {
        let line = #"{"type":"session","id":"x","timestamp":"2026-11-01T12:00:00.000Z","cwd":"/fixture/secret"}"#
        let event = PiUsageImporter().parseLine(line)
        guard event == nil else {
            failures.append("session cwd line must not become a ledger event")
            return
        }
        let labels = Mirror(reflecting: LocalUsageEvent(
            id: "pi:x",
            providerKind: .pi,
            timestamp: .now,
            model: "m",
            underlyingProvider: "anthropic",
            inputTokens: 1,
            cachedInputTokens: 0,
            cacheCreationTokens: 0,
            outputTokens: 1,
            reasoningTokens: 0
        )).children.compactMap { $0.label?.lowercased() }
        let forbidden = ["prompt", "cwd", "path", "credential", "content", "response"]
        if let leak = labels.first(where: { label in forbidden.contains(where: { label.contains($0) }) }) {
            failures.append("LocalUsageEvent exposes forbidden field \(leak)")
        }
    }

    private static func checkUnknownModelCostIncomplete(failures: inout [String]) async {
        let result = UsageCosting(catalog: PricingCatalog(revision: "empty", rates: [:])).estimate([
            PricingTokenUsage(model: "pi-unpriced-model", inputTokens: 10, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 5)
        ])
        guard !result.isComplete, result.estimate.unpricedTokens == 15 else {
            failures.append("unpriced Pi model must mark cost incomplete while preserving tokens")
            return
        }
    }

    private static func checkRetentionPrune(failures: inout [String]) async {
        let root = temporaryRoot("pi-prune")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let ledger = try CodexUsageLedger(directory: root)
            let old = LocalUsageEvent(
                id: "pi:old",
                providerKind: .pi,
                timestamp: Date(timeIntervalSince1970: 1),
                model: "old",
                underlyingProvider: "anthropic",
                inputTokens: 1,
                cachedInputTokens: 0,
                cacheCreationTokens: 0,
                outputTokens: 1,
                reasoningTokens: 0
            )
            let recent = LocalUsageEvent(
                id: "pi:new",
                providerKind: .pi,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                model: "new",
                underlyingProvider: "openai",
                inputTokens: 2,
                cachedInputTokens: 0,
                cacheCreationTokens: 0,
                outputTokens: 2,
                reasoningTokens: 0
            )
            try await ledger.replaceLocal(provider: .pi, events: [old, recent])
            try await ledger.pruneLocalHistory(provider: .pi, before: Date(timeIntervalSince1970: 1_000))
            let kept = try await ledger.local(
                provider: .pi,
                range: UsageDateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2_000_000_000))
            )
            guard kept.records == 1, kept.totalTokens == 4 else {
                failures.append("90-day prune should retain only recent Pi rows (\(kept.records)/\(kept.totalTokens))")
                return
            }
        } catch {
            failures.append("Pi prune check failed: \(error)")
        }
    }

    private static func fixtureURL() -> URL {
        let candidates = [
            URL(fileURLWithPath: "stats/Features/Usage/Fixtures/pi-session.fixture.jsonl"),
            URL(fileURLWithPath: "../stats/Features/Usage/Fixtures/pi-session.fixture.jsonl")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        fatalError("pi-session.fixture.jsonl not found")
    }

    private static func temporaryRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "stats-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
