import Foundation
import Security

struct CursorUsageEvent: Sendable, Hashable {
    let identifier: String
    let timestamp: Date
    let model: String?
    let inputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let outputTokens: Int
    var totalTokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens }
}

struct CursorUsagePage: Sendable {
    let totalCount: Int
    let events: [CursorUsageEvent]
}

enum CursorUsageClientError: LocalizedError, Sendable {
    case invalidSession, invalidResponse, incompletePages, rejectedScope
    var errorDescription: String? {
        switch self {
        case .invalidSession: "Cursor sign-in is missing or expired. Reconnect Cursor."
        case .invalidResponse: "Cursor returned usage data in an unsupported format."
        case .incompletePages: "Cursor usage pages were incomplete. No partial total was published."
        case .rejectedScope: "Cursor did not confirm the selected workspace scope."
        }
    }
}

protocol CursorUsageTransport: Sendable {
    func page(sessionToken: String, start: Date, end: Date, page: Int, pageSize: Int) async throws -> Data
}

struct URLSessionCursorUsageTransport: CursorUsageTransport {
    func page(sessionToken: String, start: Date, end: Date, page: Int, pageSize: Int) async throws -> Data {
        let url = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!
        let body: [String: Any] = ["startDate": String(Int(start.timeIntervalSince1970 * 1_000)), "endDate": String(Int(end.timeIntervalSince1970 * 1_000)), "page": page, "pageSize": pageSize]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("WorkosCursorSessionToken=\(sessionToken)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CursorUsageClientError.invalidSession }
        return data
    }
}

struct CursorUsageClient: Sendable {
    let transport: any CursorUsageTransport
    init(transport: any CursorUsageTransport = URLSessionCursorUsageTransport()) { self.transport = transport }

    func fetchToday(sessionToken: String, now: Date = .now, calendar: Calendar = .current) async throws -> [CursorUsageEvent] {
        let start = calendar.startOfDay(for: now)
        var expected: Int?
        var events: [CursorUsageEvent] = []
        for page in 1... {
            let data = try await transport.page(sessionToken: sessionToken, start: start, end: now, page: page, pageSize: 100)
            let parsed = try parse(data)
            guard expected == nil || expected == parsed.totalCount else { throw CursorUsageClientError.incompletePages }
            expected = parsed.totalCount
            events += parsed.events
            if events.count == parsed.totalCount { return events }
            guard events.count < parsed.totalCount, !parsed.events.isEmpty else { throw CursorUsageClientError.incompletePages }
        }
        throw CursorUsageClientError.incompletePages
    }

    func parse(_ data: Data) throws -> CursorUsagePage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let total = integer(root["totalUsageEventsCount"]), total >= 0, let rawEvents = root["usageEventsDisplay"] as? [[String: Any]] else { throw CursorUsageClientError.invalidResponse }
        let events = try rawEvents.map { event -> CursorUsageEvent in
            guard let timestamp = number(event["timestamp"]), timestamp >= 0 else { throw CursorUsageClientError.invalidResponse }
            let usage = event["tokenUsage"] as? [String: Any] ?? [:]
            let input = try nonnegative(usage["inputTokens"]), cacheRead = try nonnegative(usage["cacheReadTokens"]), cacheWrite = try nonnegative(usage["cacheWriteTokens"]), output = try nonnegative(usage["outputTokens"])
            let identity = "\(Int(timestamp))-\(event["model"] as? String ?? "unknown")-\(input)-\(cacheRead)-\(cacheWrite)-\(output)"
            return CursorUsageEvent(identifier: identity, timestamp: Date(timeIntervalSince1970: timestamp / 1_000), model: event["model"] as? String, inputTokens: input, cacheReadTokens: cacheRead, cacheWriteTokens: cacheWrite, outputTokens: output)
        }
        return CursorUsagePage(totalCount: total, events: events)
    }

    private func nonnegative(_ value: Any?) throws -> Int { guard let value else { return 0 }; guard let parsed = integer(value), parsed >= 0 else { throw CursorUsageClientError.invalidResponse }; return parsed }
    private func integer(_ value: Any?) -> Int? { number(value).flatMap { $0.rounded() == $0 ? Int($0) : nil } }
    private func number(_ value: Any?) -> Double? { if let number = value as? NSNumber { return number.doubleValue }; if let string = value as? String { return Double(string) }; return nil }
}

struct CursorCredential: Codable, Sendable {
    let accountID: String
    let workspaceID: String
    let workspaceName: String
    let sessionToken: String
}

struct CursorCredentialVault: Sendable {
    private static let service = "aestech.stats.cursor"
    func load() throws -> CursorCredential? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CursorUsageClientError.invalidSession }
        return try JSONDecoder().decode(CursorCredential.self, from: data)
    }
    func save(_ credential: CursorCredential) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credential)]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = attributes[kSecValueData as String]; guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw CursorUsageClientError.invalidSession }
        }
    }
}
