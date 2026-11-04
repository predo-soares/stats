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
    case invalidSession, invalidResponse, usageEventsUnavailable, incompletePages, rejectedScope
    var errorDescription: String? {
        switch self {
        case .invalidSession: "Cursor sign-in is missing or expired. Reconnect Cursor."
        case .invalidResponse: "Cursor returned usage data in an unsupported format."
        case .usageEventsUnavailable: "Cursor did not return timestamped token events for this account."
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
        try await fetchDay(sessionToken: sessionToken, start: calendar.startOfDay(for: now), asOf: now, calendar: calendar)
    }

    func fetchDay(sessionToken: String, start: Date, asOf: Date, calendar: Calendar = .current) async throws -> [CursorUsageEvent] {
        guard let nextDay = calendar.dateInterval(of: .day, for: start)?.end else {
            throw CursorUsageClientError.invalidResponse
        }
        let end = min(nextDay.addingTimeInterval(-0.001), asOf)
        let events = try await fetch(sessionToken: sessionToken, start: start, end: end, pageSize: 1_000)
        guard events.allSatisfy({ calendar.isDate($0.timestamp, inSameDayAs: start) }) else {
            throw CursorUsageClientError.invalidResponse
        }
        return events
    }

    /// Fetches a bounded historical window. The endpoint is paginated, so all pages are
    /// collected before returning; an empty provider response remains unavailable rather than
    /// being converted into a zero-usage history.
    func fetchHistory(sessionToken: String, now: Date = .now, days: Int = 60, calendar: Calendar = .current) async throws -> [CursorUsageEvent] {
        let boundedDays = min(max(days, 1), 60)
        let end = now
        let start = calendar.date(byAdding: .day, value: -(boundedDays - 1), to: calendar.startOfDay(for: now)) ?? calendar.startOfDay(for: now)
        return try await fetch(sessionToken: sessionToken, start: start, end: end)
    }

    func fetch(sessionToken: String, start: Date, end: Date, pageSize: Int = 100) async throws -> [CursorUsageEvent] {
        guard start <= end, pageSize > 0 else { throw CursorUsageClientError.invalidResponse }
        var expected: Int?
        var events: [CursorUsageEvent] = []
        for page in 1... {
            let data = try await transport.page(sessionToken: sessionToken, start: start, end: end, page: page, pageSize: pageSize)
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
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CursorUsageClientError.invalidResponse }
        guard root["totalUsageEventsCount"] != nil || root["usageEventsDisplay"] != nil else { throw CursorUsageClientError.usageEventsUnavailable }
        guard let total = integer(root["totalUsageEventsCount"]), total >= 0, let rawEvents = root["usageEventsDisplay"] as? [[String: Any]] else { throw CursorUsageClientError.invalidResponse }
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
    let refreshToken: String?
    let expiresAt: Date?

    var accessToken: String {
        let parts = sessionToken.components(separatedBy: "%3A%3A")
        return parts.count >= 2 ? parts.dropFirst().joined(separator: "%3A%3A") : sessionToken
    }

    /// Cursor's dashboard session identity is encoded in the access token subject. The
    /// persisted account ID is retained for ledger/workspace identity, but must not be
    /// trusted as the cookie prefix after a token renewal or account switch.
    var sessionAccountID: String {
        Self.accountID(from: accessToken) ?? accountID
    }

    /// Cursor's dashboard cookie is always encoded as account ID plus access token.
    /// Rebuilding it also repairs credentials saved by earlier builds that stored only
    /// the JWT in `sessionToken`.
    var sessionCookie: String {
        "\(sessionAccountID)%3A%3A\(accessToken)"
    }

    static func accountID(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = root["sub"] as? String,
              !subject.isEmpty
        else { return nil }
        let subjectParts = subject.split(separator: "|", omittingEmptySubsequences: false)
        return String(subjectParts.count > 1 ? subjectParts[1] : subjectParts[0])
    }

    init(
        accountID: String,
        workspaceID: String,
        workspaceName: String,
        sessionToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.accountID = accountID
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.sessionToken = sessionToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
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

    func clear() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CursorUsageClientError.invalidSession }
    }
}
