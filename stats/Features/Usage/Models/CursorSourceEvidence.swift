import Foundation

/// A redacted, user-inspectable summary of what the Cursor source returned and what the
/// local ledger retained. It deliberately excludes credentials, prompts, source code, IDs,
/// and raw provider payloads.
struct CursorSourceEvidence: Codable, Sendable {
    let accountFingerprint: String
    let generatedAt: Date
    let currentProbe: CursorSourceProbe
    let windows: [CursorEvidenceWindow]
    let importRanges: [CursorEvidenceImportRange]
}

struct CursorSourceProbe: Codable, Sendable {
    let requestedStart: Date
    let requestedEnd: Date
    let outcome: String
    let eventCount: Int
    let tokenSubtotal: Int
    let earliestEvent: Date?
    let latestEvent: Date?
    let message: String?
}

struct CursorEvidenceWindow: Codable, Sendable, Identifiable {
    let label: String
    let requestedStart: Date
    let requestedEnd: Date
    let eventCount: Int
    let tokenSubtotal: Int
    let earliestEvent: Date?
    let latestEvent: Date?
    let coverage: String
    var id: String { label }
}

struct CursorEvidenceImportRange: Codable, Sendable, Identifiable {
    let requestedStart: Date
    let requestedEnd: Date
    let state: String
    let retryAfter: Date?
    let message: String?
    let updatedAt: Date
    var id: String { "\(requestedStart.timeIntervalSince1970)-\(requestedEnd.timeIntervalSince1970)" }
}

extension CursorCredential {
    var redactedAccountFingerprint: String {
        guard accountID.count > 8 else { return "Connected Cursor account" }
        return "\(accountID.prefix(8))…\(accountID.suffix(4))"
    }
}
