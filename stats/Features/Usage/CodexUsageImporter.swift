import CryptoKit
import Foundation

struct CodexUsageImporter: Sendable {
    let sessionsURL: URL
    nonisolated init(sessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions", directoryHint: .isDirectory)) { self.sessionsURL = sessionsURL }

    nonisolated func importAvailableSessions(into ledger: CodexUsageLedger) throws -> CodexUsageProjection {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else { return try ledger.today(now: .now) }
        let enumerator = FileManager.default.enumerator(at: sessionsURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        let files = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
        var events: [CodexUsageEvent] = []
        for file in files { events.append(contentsOf: try parse(file)) }
        // `total_token_usage` is a cumulative transcript snapshot. Rebuild this derived table
        // from raw source files so replacing the normalizer repairs earlier imports safely.
        try ledger.replaceCodex(events)
        return try ledger.today(now: .now)
    }

    private nonisolated func parse(_ file: URL) throws -> [CodexUsageEvent] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let raw = Data(line.utf8)
            guard let object = try? JSONSerialization.jsonObject(with: raw),
                  let dictionary = object as? [String: Any],
                  dictionary["type"] as? String == "event_msg",
                  let payload = dictionary["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let usage = (payload["info"] as? [String: Any])?["last_token_usage"] as? [String: Any],
                  let timestamp = date(from: dictionary["timestamp"]),
                  let counts = tokenCounts(in: usage),
                  counts.total > 0
            else { return nil }
            let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
            return CodexUsageEvent(identifier: digest, timestamp: timestamp, inputTokens: counts.input, cachedInputTokens: counts.cached, outputTokens: counts.output, sourceFile: file.lastPathComponent)
        }
    }

    private nonisolated func date(from value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private nonisolated func tokenCounts(in usage: [String: Any]) -> (input: Int, cached: Int, output: Int, total: Int)? {
        guard let inclusiveInput = integer(usage["input_tokens"]),
              let output = integer(usage["output_tokens"])
        else { return nil }
        let cached = integer(usage["cached_input_tokens"] ?? usage["cache_read_input_tokens"]) ?? 0
        guard inclusiveInput >= cached, output >= 0 else { return nil }
        return (inclusiveInput - cached, cached, output, inclusiveInput + output)
    }
    private nonisolated func integer(_ value: Any?) -> Int? { if let value = value as? Int { return value }; return (value as? NSNumber)?.intValue }
}
