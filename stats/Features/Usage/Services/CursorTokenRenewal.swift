import Foundation

protocol CursorTokenRenewalTransport: Sendable {
    func renew(refreshToken: String) async throws -> (status: Int, body: Data)
}

struct URLSessionCursorTokenRenewalTransport: CursorTokenRenewalTransport {
    static let url = URL(string: "https://api2.cursor.sh/oauth/token")!
    static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    func renew(refreshToken: String) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CursorBrowserAuthenticationError.invalidResponse }
        return (response.statusCode, data)
    }
}

/// Cursor access tokens are 60-day JWTs that also act as refresh tokens. Renew a week early so
/// overnight Mac sleep around expiry does not drop the connection.
struct CursorTokenRenewal: Sendable {
    static let refreshLead: TimeInterval = 7 * 86_400

    let transport: any CursorTokenRenewalTransport
    let now: @Sendable () -> Date

    init(
        transport: any CursorTokenRenewalTransport = URLSessionCursorTokenRenewalTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.now = now
    }

    func needsRenewal(_ credential: CursorCredential) -> Bool {
        guard let expiresAt = credential.expiresAt ?? jwtExpiry(credential.accessToken) else { return false }
        return expiresAt.addingTimeInterval(-Self.refreshLead) <= now()
    }

    func renew(_ credential: CursorCredential) async throws -> CursorCredential {
        let refreshToken = credential.refreshToken ?? credential.accessToken
        let response = try await transport.renew(refreshToken: refreshToken)
        guard (200..<300).contains(response.status) else { throw CursorUsageClientError.invalidSession }
        guard let root = try JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw CursorBrowserAuthenticationError.invalidResponse
        }
        if root["shouldLogout"] as? Bool == true { throw CursorUsageClientError.invalidSession }
        guard let accessToken = (root["access_token"] as? String) ?? (root["accessToken"] as? String), !accessToken.isEmpty else {
            throw CursorBrowserAuthenticationError.invalidResponse
        }
        let nextRefresh = (root["refresh_token"] as? String) ?? (root["refreshToken"] as? String) ?? accessToken
        let nextAccountID = CursorCredential.accountID(from: accessToken) ?? credential.accountID
        return CursorCredential(
            accountID: nextAccountID,
            workspaceID: credential.workspaceID,
            workspaceName: credential.workspaceName,
            sessionToken: "\(nextAccountID)%3A%3A\(accessToken)",
            refreshToken: nextRefresh,
            expiresAt: jwtExpiry(accessToken)
        )
    }

    func jwtExpiry(_ accessToken: String) -> Date? {
        let parts = accessToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let exp: Double?
        if let value = root["exp"] as? Double { exp = value }
        else if let value = root["exp"] as? Int { exp = Double(value) }
        else if let value = root["exp"] as? NSNumber { exp = value.doubleValue }
        else { exp = nil }
        guard let exp else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

}
