import Foundation

private struct FixtureAuthTransport: CursorBrowserAuthenticationTransport {
    let status: Int
    let body: Data

    func poll(id: UUID, verifier: String) async throws -> (status: Int, body: Data) {
        (status, body)
    }
}

private struct FixtureRenewalTransport: CursorTokenRenewalTransport {
    let status: Int
    let body: Data

    func renew(refreshToken: String) async throws -> (status: Int, body: Data) {
        (status, body)
    }
}

private struct FixtureWorkspaceSource: CursorWorkspaceScopeSource {
    let scopes: [CursorWorkspaceScope]

    func availableScopes(for session: CursorAuthenticatedSession) async throws -> [CursorWorkspaceScope] {
        scopes
    }
}

@main
struct RunCursorConnectionSelfChecks {
    static func main() async {
        var failures: [String] = []
        await checkAuthenticationDecode(failures: &failures)
        await checkRejectedSignIn(failures: &failures)
        checkWorkspaceSelection(failures: &failures)
        checkRejectedUnknownWorkspace(failures: &failures)
        await checkTokenRenewalPersistsAccessToken(failures: &failures)
        await checkWorkspaceHistoriesStayIsolated(failures: &failures)

        if failures.isEmpty {
            print("PASS: Cursor connection, renewal, and workspace isolation checks")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func checkAuthenticationDecode(failures: inout [String]) async {
        let token = fakeJWT(sub: "auth0|acct-1", exp: 4_000_000_000)
        let body = Data(#"{"accessToken":"\#(token)","refreshToken":"\#(token)"}"#.utf8)
        let auth = CursorBrowserAuthentication(transport: FixtureAuthTransport(status: 200, body: body))
        do {
            let authorization = try auth.begin()
            let session = try await auth.awaitCompletion(for: authorization, maximumAttempts: 1)
            guard session.accountID == "acct-1", session.accessToken == token, session.refreshToken == token else {
                failures.append("authenticated session decode lost account or tokens")
                return
            }
        } catch {
            failures.append("authentication decode failed: \(error)")
        }
    }

    private static func checkRejectedSignIn(failures: inout [String]) async {
        let auth = CursorBrowserAuthentication(transport: FixtureAuthTransport(status: 401, body: Data()))
        do {
            let authorization = try auth.begin()
            _ = try await auth.awaitCompletion(for: authorization, maximumAttempts: 1)
            failures.append("rejected Cursor sign-in was accepted")
        } catch CursorBrowserAuthenticationError.signInRejected {
        } catch {
            failures.append("rejected Cursor sign-in returned the wrong error")
        }
    }

    private static func checkWorkspaceSelection(failures: inout [String]) {
        let scopes = [
            CursorWorkspaceScope(id: "a", name: "Personal"),
            CursorWorkspaceScope(id: "b", name: "Team")
        ]
        do {
            _ = try CursorWorkspaceSelection.resolve(scopes: scopes, preferredID: nil)
            failures.append("ambiguous workspaces were auto-selected")
        } catch CursorWorkspaceScopeError.ambiguousSelection(let exposed) {
            if exposed != scopes { failures.append("ambiguous selection lost exposed scopes") }
        } catch {
            failures.append("ambiguous selection returned the wrong error")
        }
        do {
            let selected = try CursorWorkspaceSelection.resolve(scopes: scopes, preferredID: "b")
            if selected.scope.id != "b" { failures.append("preferred workspace was not selected") }
        } catch {
            failures.append("preferred workspace selection failed")
        }
    }

    private static func checkRejectedUnknownWorkspace(failures: inout [String]) {
        let scopes = [CursorWorkspaceScope(id: "a", name: "Personal")]
        do {
            _ = try CursorWorkspaceSelection.resolve(scopes: scopes, preferredID: "missing")
            failures.append("unknown workspace scope was accepted")
        } catch CursorWorkspaceScopeError.unknownScope {
        } catch {
            failures.append("unknown workspace returned the wrong error")
        }
    }

    private static func checkTokenRenewalPersistsAccessToken(failures: inout [String]) async {
        let oldToken = fakeJWT(sub: "auth0|acct-1", exp: 1_700_100_000)
        let newToken = fakeJWT(sub: "auth0|acct-1", exp: 1_710_000_000)
        let renewal = CursorTokenRenewal(
            transport: FixtureRenewalTransport(
                status: 200,
                body: Data(#"{"access_token":"\#(newToken)","shouldLogout":false}"#.utf8)
            ),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let credential = CursorCredential(
            accountID: "acct-1",
            workspaceID: "default:acct-1",
            workspaceName: "Default workspace",
            sessionToken: "acct-1%3A%3A\(oldToken)",
            refreshToken: oldToken,
            expiresAt: Date(timeIntervalSince1970: 1_700_100_000)
        )
        guard renewal.needsRenewal(credential) else {
            failures.append("near-expiry Cursor token was not marked for renewal")
            return
        }
        do {
            let renewed = try await renewal.renew(credential)
            guard renewed.accessToken == newToken, renewed.refreshToken == newToken, renewed.workspaceID == credential.workspaceID else {
                failures.append("token renewal did not preserve workspace or replace access token")
                return
            }
        } catch {
            failures.append("token renewal failed: \(error)")
        }
    }

    private static func checkWorkspaceHistoriesStayIsolated(failures: inout [String]) async {
        let root = FileManager.default.temporaryDirectory.appending(path: "stats-cursor-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let ledger = try CodexUsageLedger(directory: root)
            let personal = [
                CursorUsageEvent(identifier: "p1", timestamp: Date(timeIntervalSince1970: 1_700_000_100), model: "a", inputTokens: 10, cacheReadTokens: 1, cacheWriteTokens: 0, outputTokens: 2)
            ]
            let team = [
                CursorUsageEvent(identifier: "t1", timestamp: Date(timeIntervalSince1970: 1_700_000_100), model: "a", inputTokens: 100, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 20)
            ]
            try await ledger.upsertCursor(personal, workspaceID: "default:acct-1")
            try await ledger.upsertCursor(team, workspaceID: "team:acct-1")
            let personalToday = try await ledger.cursorToday(
                workspaceID: "default:acct-1",
                workspaceName: "Default workspace",
                now: Date(timeIntervalSince1970: 1_700_000_800),
                calendar: utcCalendar
            )
            let teamToday = try await ledger.cursorToday(
                workspaceID: "team:acct-1",
                workspaceName: "Team",
                now: Date(timeIntervalSince1970: 1_700_000_800),
                calendar: utcCalendar
            )
            guard personalToday.totalTokens == 13, teamToday.totalTokens == 120 else {
                failures.append("workspace histories were mixed in the ledger")
                return
            }
        } catch {
            failures.append("workspace isolation check failed: \(error)")
        }
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func fakeJWT(sub: String, exp: Int) -> String {
        let payload = #"{"sub":"\#(sub)","exp":\#(exp),"type":"session"}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(encoded).fake-signature"
    }
}
