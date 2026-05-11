import Foundation

private struct DiagnosticsPersistencePayload: Codable, Sendable {
    var version: Int
    var activeEvents: [DiagnosticsIssueEvent]
    var resolvedEvents: [DiagnosticsIssueEvent]
}

actor DiagnosticsPersistence {
    private let fileName = "diagnostics-history.json"
    private let baseDirectoryURL: URL?

    init(baseDirectoryURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func load() async -> (active: [DiagnosticsIssueEvent], resolved: [DiagnosticsIssueEvent]) {
        guard let url = try? fileURL(),
              let data = try? Data(contentsOf: url) else {
            return ([], [])
        }

        let payload = try? await MainActor.run(resultType: DiagnosticsPersistencePayload.self) {
            return try decodePayload(from: data)
        }

        guard let payload else {
            return ([], [])
        }

        return (payload.activeEvents, payload.resolvedEvents)
    }

    func save(active: [DiagnosticsIssueEvent], resolved: [DiagnosticsIssueEvent]) async {
        let payload = DiagnosticsPersistencePayload(version: 1, activeEvents: active, resolvedEvents: resolved)
        let url = try? fileURL()
        let data = try? await MainActor.run(resultType: Data.self) {
            try encodePayload(payload)
        }

        guard let data,
              let url else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        guard let url = try? fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func fileURL() throws -> URL {
        if let baseDirectoryURL {
            try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
            return baseDirectoryURL.appendingPathComponent(fileName)
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("stats", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    @MainActor
    private func decodePayload(from data: Data) throws -> DiagnosticsPersistencePayload {
        try JSONDecoder().decode(DiagnosticsPersistencePayload.self, from: data)
    }

    @MainActor
    private func encodePayload(_ payload: DiagnosticsPersistencePayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }
}
