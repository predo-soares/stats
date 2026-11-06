import Foundation

/// Imports sanitized Claude Code JSONL session metadata into normalized local events.
struct ClaudeUsageImporter: Sendable {
    let projectsURL: URL

    init(
        projectsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects", directoryHint: .isDirectory)
    ) {
        self.projectsURL = projectsURL
    }

    var isSourceAvailable: Bool {
        FileManager.default.fileExists(atPath: projectsURL.path)
    }

    enum ClaudeImportError: Error, Equatable {
        case sourceMissing
    }

    func importEvents() throws -> [LocalUsageEvent] {
        guard isSourceAvailable else { throw ClaudeImportError.sourceMissing }
        let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
        var events: [LocalUsageEvent] = []
        var seen = Set<String>()
        for file in files {
            for event in try parse(file) where seen.insert(event.id).inserted {
                events.append(event)
            }
        }
        return events
    }

    func importAvailableSessions(into ledger: CodexUsageLedger, now: Date = .now) async throws -> LocalUsageProjection {
        guard isSourceAvailable else {
            return try await ledger.localToday(provider: .claude, now: now)
        }
        let events = try importEvents()
        try await ledger.replaceLocal(provider: .claude, events: events)
        let retention = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
        try await ledger.pruneLocalHistory(provider: .claude, before: retention)
        return try await ledger.localToday(provider: .claude, now: now)
    }

    /// Parses a single JSONL file. Only assistant usage metadata is retained.
    func parse(_ file: URL) throws -> [LocalUsageEvent] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            parseLine(String(line))
        }
    }

    func parseLine(_ line: String) -> LocalUsageEvent? {
        guard let raw = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw),
              let dictionary = object as? [String: Any],
              dictionary["type"] as? String == "assistant",
              let timestamp = date(from: dictionary["timestamp"]),
              let message = dictionary["message"] as? [String: Any],
              let model = message["model"] as? String,
              !model.localizedCaseInsensitiveContains("synthetic"),
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        let input = integer(usage["input_tokens"]) ?? 0
        let output = integer(usage["output_tokens"]) ?? 0
        let cached = integer(usage["cache_read_input_tokens"]) ?? 0
        let cacheCreation = integer(usage["cache_creation_input_tokens"]) ?? 0
        guard input + output + cached + cacheCreation > 0 else { return nil }

        let messageID = (message["id"] as? String) ?? "msg"
        let requestID = (dictionary["requestId"] as? String) ?? (dictionary["request_id"] as? String) ?? "req"
        let sessionID = (dictionary["sessionId"] as? String) ?? (dictionary["session_id"] as? String) ?? "sess"
        // Opaque synthetic identity — not a filesystem path.
        let identifier = "claude:\(sessionID):\(requestID):\(messageID)"

        return LocalUsageEvent(
            id: identifier,
            providerKind: .claude,
            timestamp: timestamp,
            model: model,
            underlyingProvider: nil,
            inputTokens: input,
            cachedInputTokens: cached,
            cacheCreationTokens: cacheCreation,
            outputTokens: output,
            reasoningTokens: 0
        )
    }

    private func date(from value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}
