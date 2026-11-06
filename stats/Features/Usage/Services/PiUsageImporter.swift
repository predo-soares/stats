import Foundation

/// Imports sanitized Pi runtime session metadata with underlying provider provenance.
struct PiUsageImporter: Sendable {
    let sessionsURL: URL

    init(
        sessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".pi/agent/sessions", directoryHint: .isDirectory)
    ) {
        self.sessionsURL = sessionsURL
    }

    var isSourceAvailable: Bool {
        FileManager.default.fileExists(atPath: sessionsURL.path)
    }

    enum PiImportError: Error, Equatable {
        case sourceMissing
    }

    func importEvents() throws -> [LocalUsageEvent] {
        guard isSourceAvailable else { throw PiImportError.sourceMissing }
        let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
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

    func parse(_ file: URL) throws -> [LocalUsageEvent] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    func parseLine(_ line: String) -> LocalUsageEvent? {
        guard let raw = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw),
              let dictionary = object as? [String: Any],
              let type = dictionary["type"] as? String
        else { return nil }

        switch type {
        case "message":
            return parseMessage(dictionary)
        case "usage":
            return parseUsage(dictionary)
        default:
            // session headers may include cwd — never retained.
            return nil
        }
    }

    private func parseMessage(_ dictionary: [String: Any]) -> LocalUsageEvent? {
        guard let timestamp = date(from: dictionary["timestamp"]),
              let message = dictionary["message"] as? [String: Any],
              (message["role"] as? String) == "assistant",
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any]
        else { return nil }
        return makeEvent(
            id: dictionary["id"] as? String,
            timestamp: timestamp,
            model: model,
            underlyingProvider: message["provider"] as? String,
            usage: usage
        )
    }

    private func parseUsage(_ dictionary: [String: Any]) -> LocalUsageEvent? {
        guard let timestamp = date(from: dictionary["timestamp"]),
              let model = dictionary["model"] as? String,
              let usage = dictionary["usage"] as? [String: Any]
        else { return nil }
        return makeEvent(
            id: dictionary["id"] as? String,
            timestamp: timestamp,
            model: model,
            underlyingProvider: dictionary["provider"] as? String,
            usage: usage
        )
    }

    private func makeEvent(
        id: String?,
        timestamp: Date,
        model: String,
        underlyingProvider: String?,
        usage: [String: Any]
    ) -> LocalUsageEvent? {
        let input = integer(usage["input"]) ?? 0
        let output = integer(usage["output"]) ?? 0
        let cached = integer(usage["cacheRead"]) ?? 0
        let cacheWrite = integer(usage["cacheWrite"]) ?? 0
        let reasoning = integer(usage["reasoning"]) ?? 0
        guard input + output + cached + cacheWrite + reasoning > 0 else { return nil }
        let opaqueID = id ?? UUID().uuidString
        return LocalUsageEvent(
            id: "pi:\(opaqueID)",
            providerKind: .pi,
            timestamp: timestamp,
            model: model,
            underlyingProvider: underlyingProvider,
            inputTokens: input,
            cachedInputTokens: cached,
            cacheCreationTokens: cacheWrite,
            outputTokens: output,
            reasoningTokens: reasoning
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
