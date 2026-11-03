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
        try ledger.upsert(events)
        return try ledger.today(now: .now)
    }

    private nonisolated func parse(_ file: URL) throws -> [CodexUsageEvent] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let raw = Data(line.utf8)
            guard let object = try? JSONSerialization.jsonObject(with: raw), let dictionary = object as? [String: Any], let timestamp = date(from: dictionary["timestamp"]), let counts = tokenCounts(in: dictionary), counts.total > 0 else { return nil }
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
    private nonisolated func tokenCounts(in value: Any) -> (input: Int, cached: Int, output: Int, total: Int)? {
        if let dictionary = value as? [String: Any] {
            let input = integer(dictionary["input_tokens"]), cached = integer(dictionary["cached_input_tokens"]), output = integer(dictionary["output_tokens"])
            if input != nil || cached != nil || output != nil { let cache = cached ?? 0; return (max(0, (input ?? 0) - cache), cache, output ?? 0, (input ?? 0) + (output ?? 0)) }
            for child in dictionary.values { if let found = tokenCounts(in: child) { return found } }
        } else if let array = value as? [Any] { for child in array { if let found = tokenCounts(in: child) { return found } } }
        return nil
    }
    private nonisolated func integer(_ value: Any?) -> Int? { if let value = value as? Int { return value }; return (value as? NSNumber)?.intValue }
}
