import CryptoKit
import Foundation
import Security

/// In-memory state for one app-owned Cursor sign-in. The verifier and tokens are never written to
/// the usage ledger; callers may save the authenticated account's default scope through
/// `CursorCredentialVault` after sign-in completes.
struct CursorBrowserAuthorization: Sendable {
    let id: UUID
    let verifier: String
    let browserURL: URL
}

struct CursorAuthenticatedSession: Sendable {
    let accountID: String
    let accessToken: String
    let refreshToken: String

    func credential(workspaceID: String, workspaceName: String, expiresAt: Date? = nil) -> CursorCredential {
        CursorCredential(
            accountID: accountID,
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            sessionToken: "\(accountID)%3A%3A\(accessToken)",
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}

enum CursorBrowserAuthenticationError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case signInRejected
    case signInTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Cursor sign-in URL could not be created."
        case .invalidResponse: "Cursor returned an invalid sign-in response."
        case .signInRejected: "Cursor sign-in was rejected."
        case .signInTimedOut: "Cursor sign-in timed out. Start the connection again."
        }
    }
}

protocol CursorBrowserAuthenticationTransport: Sendable {
    func poll(id: UUID, verifier: String) async throws -> (status: Int, body: Data)
}

struct URLSessionCursorBrowserAuthenticationTransport: CursorBrowserAuthenticationTransport {
    func poll(id: UUID, verifier: String) async throws -> (status: Int, body: Data) {
        var components = URLComponents(string: "https://api2.cursor.sh/auth/poll")
        components?.queryItems = [URLQueryItem(name: "uuid", value: id.uuidString), URLQueryItem(name: "verifier", value: verifier)]
        guard let url = components?.url else { throw CursorBrowserAuthenticationError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw CursorBrowserAuthenticationError.invalidResponse }
        return (response.statusCode, data)
    }
}

struct CursorBrowserAuthentication: Sendable {
    let transport: any CursorBrowserAuthenticationTransport

    init(transport: any CursorBrowserAuthenticationTransport = URLSessionCursorBrowserAuthenticationTransport()) {
        self.transport = transport
    }

    func begin() throws -> CursorBrowserAuthorization {
        let verifier = Self.randomURLSafeString(bytes: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Self.base64URL(Data(digest))
        let id = UUID()
        var components = URLComponents(string: "https://cursor.com/loginDeepControl")
        components?.queryItems = [
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "uuid", value: id.uuidString),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: "cli")
        ]
        guard let browserURL = components?.url else { throw CursorBrowserAuthenticationError.invalidURL }
        return CursorBrowserAuthorization(id: id, verifier: verifier, browserURL: browserURL)
    }

    /// Poll after the user has opened `CursorBrowserAuthorization.browserURL`. Polling stops after
    /// five minutes, matching Cursor's observed sign-in window.
    func awaitCompletion(for authorization: CursorBrowserAuthorization, maximumAttempts: Int = 150) async throws -> CursorAuthenticatedSession {
        for _ in 0..<maximumAttempts {
            try Task.checkCancellation()
            let response = try await transport.poll(id: authorization.id, verifier: authorization.verifier)
            if response.status == 202 || response.status == 404 {
                try await Task.sleep(for: .seconds(2))
                continue
            }
            guard (200..<300).contains(response.status) else { throw CursorBrowserAuthenticationError.signInRejected }
            return try decode(response.body)
        }
        throw CursorBrowserAuthenticationError.signInTimedOut
    }

    private func decode(_ data: Data) throws -> CursorAuthenticatedSession {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = root["accessToken"] as? String, !accessToken.isEmpty,
              let refreshToken = root["refreshToken"] as? String, !refreshToken.isEmpty,
              let accountID = Self.accountID(from: accessToken)
        else { throw CursorBrowserAuthenticationError.invalidResponse }
        return CursorAuthenticatedSession(accountID: accountID, accessToken: accessToken, refreshToken: refreshToken)
    }

    private static func accountID(from accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let subject = root["sub"] as? String else { return nil }
        let subjectParts = subject.split(separator: "|", omittingEmptySubsequences: false)
        return String(subjectParts.count > 1 ? subjectParts[1] : subjectParts[0])
    }

    private static func randomURLSafeString(bytes: Int) -> String {
        var values = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, values.count, &values)
        return base64URL(Data(values))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
