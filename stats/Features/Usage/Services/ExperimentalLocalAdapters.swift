import Foundation
import Security

/// Shared Experimental adapters for Grok (local signals), Z.ai (credentialed API fixture),
/// and Antigravity (status-line snapshots). Each parses sanitized fixtures only.
enum ExperimentalLocalAdapters {
    static let retentionDays = 90
}

struct GrokUsageImporter: Sendable {
    let sessionsURL: URL

    init(
        sessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".grok/sessions", directoryHint: .isDirectory)
    ) {
        self.sessionsURL = sessionsURL
    }

    var isSourceAvailable: Bool { FileManager.default.fileExists(atPath: sessionsURL.path) }

    enum ImportError: Error { case sourceMissing }

    func importEvents() throws -> [LocalUsageEvent] {
        guard isSourceAvailable else { throw ImportError.sourceMissing }
        let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let files = (enumerator?.allObjects as? [URL] ?? []).filter {
            $0.pathExtension == "jsonl" || $0.lastPathComponent.hasSuffix(".fixture.jsonl")
        }
        var transcripts: [LocalUsageEvent] = []
        var signals: [LocalUsageEvent] = []
        var seen = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(whereSeparator: \.isNewline) {
                guard let parsed = parseLine(String(line)) else { continue }
                let event = parsed.event
                guard seen.insert(event.id).inserted else { continue }
                if parsed.isTranscript {
                    transcripts.append(event)
                } else {
                    signals.append(event)
                }
            }
        }
        // Prefer per-turn transcript rows; keep signals only for sessions without transcript coverage.
        func sessionID(from event: LocalUsageEvent) -> String {
            let parts = event.id.split(separator: ":").map(String.init)
            if event.id.hasPrefix("grok-signals:"), parts.count >= 2 { return parts[1] }
            if parts.count >= 2 { return parts[1] }
            return event.id
        }
        let transcriptSessions = Set(transcripts.map(sessionID(from:)))
        let filteredSignals = signals.filter { !transcriptSessions.contains(sessionID(from: $0)) }
        return transcripts + filteredSignals
    }

    func parseLine(_ line: String) -> (event: LocalUsageEvent, isTranscript: Bool)? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["provider"] as? String) == "grok",
              let kind = object["sourceKind"] as? String
        else { return nil }

        switch kind {
        case "local-transcript":
            return parseTranscript(object).map { ($0, true) }
        case "local-signals":
            return parseSignals(object).map { ($0, false) }
        default:
            return nil
        }
    }

    private func parseTranscript(_ object: [String: Any]) -> LocalUsageEvent? {
        let input = int(object["inputTokens"]) ?? 0
        let output = int(object["outputTokens"]) ?? 0
        let cached = int(object["cachedReadTokens"]) ?? 0
        let cacheCreation = int(object["cacheCreationTokens"]) ?? 0
        let reasoning = int(object["reasoningTokens"]) ?? 0
        guard input + output + cached + cacheCreation + reasoning > 0 else { return nil }
        let session = object["sessionId"] as? String ?? "sess"
        let prompt = object["promptId"] as? String ?? "prompt"
        let ms = (object["timestampMs"] as? NSNumber)?.doubleValue
        let timestamp = ms.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        let model = object["model"] as? String ?? object["primaryModelId"] as? String ?? "unknown"
        return LocalUsageEvent(
            id: "grok:\(session):\(prompt)",
            providerKind: .grok,
            timestamp: timestamp,
            model: model,
            underlyingProvider: "xai",
            inputTokens: input,
            cachedInputTokens: cached,
            cacheCreationTokens: cacheCreation,
            outputTokens: output,
            reasoningTokens: reasoning
        )
    }

    private func parseSignals(_ object: [String: Any]) -> LocalUsageEvent? {
        // Prefer per-turn transcript rows when both exist; signals are rollups.
        // Only keep signals when no transcript fields are present in the same batch identity.
        let before = int(object["totalTokensBeforeCompaction"]) ?? 0
        let context = int(object["contextTokensUsed"]) ?? 0
        let total = before + context
        guard total > 0 else { return nil }
        let session = object["sessionId"] as? String ?? "sess"
        let observed = (object["observedAt"] as? String).flatMap(date(from:)) ?? .now
        let model = object["primaryModelId"] as? String ?? "unknown"
        // Attribute rollup to input bucket; incomplete category split is explicit via coverage.
        return LocalUsageEvent(
            id: "grok-signals:\(session):\(Int(observed.timeIntervalSince1970))",
            providerKind: .grok,
            timestamp: observed,
            model: model,
            underlyingProvider: "xai",
            inputTokens: total,
            cachedInputTokens: 0,
            cacheCreationTokens: 0,
            outputTokens: 0,
            reasoningTokens: 0
        )
    }

    private func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}

struct ZaiUsageImporter: Sendable {
    /// Fixture or cached redacted bundle directory (never stores API keys).
    let bundleURL: URL

    init(
        bundleURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".stats/fixtures/zai", directoryHint: .isDirectory)
    ) {
        self.bundleURL = bundleURL
    }

    enum ImportError: Error { case sourceMissing, invalidBundle }

    func importEvents(usingCredentialPresent: Bool) throws -> [LocalUsageEvent] {
        guard usingCredentialPresent else { throw ImportError.sourceMissing }
        let file = bundleURL.appending(path: "zai-usage.fixture.json")
        let fallback = URL(fileURLWithPath: "stats/Features/Usage/Fixtures/zai-usage.fixture.json")
        let url = FileManager.default.fileExists(atPath: file.path) ? file : fallback
        guard FileManager.default.fileExists(atPath: url.path) else { throw ImportError.sourceMissing }
        let data = try Data(contentsOf: url)
        return try parseBundle(data)
    }

    func parseBundle(_ data: Data) throws -> [LocalUsageEvent] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelUsage = object["modelUsage"] as? [String: Any],
              let payload = modelUsage["data"] as? [String: Any],
              let models = payload["modelDataList"] as? [[String: Any]]
        else { throw ImportError.invalidBundle }
        let fetchedAt = (object["fetchedAt"] as? String).flatMap(date(from:)) ?? .now
        return models.enumerated().compactMap { index, model in
            let code = model["modelCode"] as? String ?? "unknown"
            let input = int(model["inputTokens"]) ?? 0
            let output = int(model["outputTokens"]) ?? 0
            let reasoning = int(model["reasoningTokens"]) ?? 0
            let cached = int(model["cachedTokens"]) ?? 0
            guard input + output + reasoning + cached > 0 else { return nil }
            return LocalUsageEvent(
                id: "zai:\(code):\(index)",
                providerKind: .zai,
                timestamp: fetchedAt,
                model: code,
                underlyingProvider: "zai",
                inputTokens: input,
                cachedInputTokens: cached,
                cacheCreationTokens: 0,
                outputTokens: output,
                reasoningTokens: reasoning
            )
        }
    }

    private func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}

/// Keychain-only storage for the explicit Z.ai API credential.
enum ZaiCredentialVault {
    private static let service = "aestech.stats.zai"
    private static let account = "api-key"

    static func hasCredential() -> Bool {
        (try? load()) != nil
    }

    static func save(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var values = query
        values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(values as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.saveFailed }
    }

    static func load() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw VaultError.missing
        }
        return key
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum VaultError: Error { case missing, saveFailed }
}

struct AntigravityUsageImporter: Sendable {
    let snapshotsURL: URL

    init(
        snapshotsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".stats/antigravity", directoryHint: .isDirectory)
    ) {
        self.snapshotsURL = snapshotsURL
    }

    var isSourceAvailable: Bool { FileManager.default.fileExists(atPath: snapshotsURL.path) }
    enum ImportError: Error { case sourceMissing }

    func importEvents() throws -> [LocalUsageEvent] {
        guard isSourceAvailable else { throw ImportError.sourceMissing }
        let enumerator = FileManager.default.enumerator(
            at: snapshotsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
        var events: [LocalUsageEvent] = []
        var seen = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(whereSeparator: \.isNewline) {
                if let event = parseLine(String(line)), seen.insert(event.id).inserted {
                    events.append(event)
                }
            }
        }
        return events
    }

    func parseLine(_ line: String) -> LocalUsageEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["provider"] as? String) == "antigravity",
              let tokens = object["sessionTokens"] as? [String: Any]
        else { return nil }
        let input = int(tokens["input"]) ?? 0
        let output = int(tokens["output"]) ?? 0
        let cacheRead = int(tokens["cacheRead"]) ?? 0
        // Prefer latest snapshot per session — identity includes capturedAt.
        let captured = (object["capturedAt"] as? String).flatMap(date(from:)) ?? .now
        let session = object["sessionId"] as? String ?? "sess"
        let model = object["model"] as? String ?? "unknown"
        guard input + output + cacheRead > 0 else { return nil }
        // Do not retain workspaceLabel paths/names beyond a generic tag.
        return LocalUsageEvent(
            id: "antigravity:\(session):\(Int(captured.timeIntervalSince1970))",
            providerKind: .antigravity,
            timestamp: captured,
            model: model,
            underlyingProvider: "antigravity",
            inputTokens: input,
            cachedInputTokens: cacheRead,
            cacheCreationTokens: 0,
            outputTokens: output,
            reasoningTokens: 0
        )
    }

    private func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}

struct ExperimentalLocalUsageService: Sendable {
    let kind: LocalProviderKind

    func refresh(
        into ledger: CodexUsageLedger,
        events: [LocalUsageEvent],
        outcome: LocalSourceOutcome = .imported,
        coverageOnEmpty: LocalUsageCoverage = .empty,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> (LocalUsageProjection, LocalSourceEvidence) {
        try await ledger.replaceLocal(provider: kind, events: events)
        if let cutoff = calendar.date(byAdding: .day, value: -ExperimentalLocalAdapters.retentionDays, to: now) {
            try await ledger.pruneLocalHistory(provider: kind, before: cutoff)
        }
        var projection = try await ledger.localToday(provider: kind, now: now, calendar: calendar)
        if projection.records == 0 {
            projection = .empty(coverage: coverageOnEmpty)
        }
        let evidence = try await ledger.localSourceEvidence(
            provider: kind,
            requestedWindowLabel: "Today",
            range: UsageDateRange(start: calendar.startOfDay(for: now), end: now),
            outcome: outcome,
            safeErrorReason: nil,
            now: now,
            calendar: calendar
        )
        return (projection, evidence)
    }

    func preserveFailure(
        into ledger: CodexUsageLedger,
        coverage: LocalUsageCoverage,
        outcome: LocalSourceOutcome,
        safeErrorReason: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> (LocalUsageProjection, LocalSourceEvidence) {
        var projection = try await ledger.localToday(provider: kind, now: now, calendar: calendar)
        if projection.records > 0 {
            projection = LocalUsageProjection(
                inputTokens: projection.inputTokens,
                cachedInputTokens: projection.cachedInputTokens,
                cacheCreationTokens: projection.cacheCreationTokens,
                outputTokens: projection.outputTokens,
                reasoningTokens: projection.reasoningTokens,
                cutoff: projection.cutoff,
                records: projection.records,
                coverage: coverage
            )
        } else {
            projection = .empty(coverage: coverage)
        }
        let evidence = try await ledger.localSourceEvidence(
            provider: kind,
            requestedWindowLabel: "Today",
            range: UsageDateRange(start: calendar.startOfDay(for: now), end: now),
            outcome: outcome,
            safeErrorReason: safeErrorReason,
            now: now,
            calendar: calendar
        )
        return (projection, evidence)
    }
}
