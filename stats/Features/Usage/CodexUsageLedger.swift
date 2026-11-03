import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CodexUsageEvent: Sendable {
    let identifier: String
    let timestamp: Date
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let sourceFile: String
    let model: String?

    init(identifier: String, timestamp: Date, inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, sourceFile: String, model: String? = nil) {
        self.identifier = identifier; self.timestamp = timestamp; self.inputTokens = inputTokens; self.cachedInputTokens = cachedInputTokens; self.outputTokens = outputTokens; self.sourceFile = sourceFile; self.model = model
    }
}

/// A half-open local-time query window. Keeping the end exclusive makes adjacent
/// comparison windows disjoint even when an event lands exactly on a boundary.
struct UsageDateRange: Sendable, Equatable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        precondition(start <= end)
        self.start = start
        self.end = end
    }
}

final class CodexUsageLedger: @unchecked Sendable {
    private var database: OpaquePointer?

    nonisolated init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "stats", directoryHint: .isDirectory)) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "usage-ledger.sqlite")
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw LedgerError.open }
        try execute("CREATE TABLE IF NOT EXISTS codex_usage_events (id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL, input_tokens INTEGER NOT NULL, cached_input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, source_file TEXT NOT NULL, model TEXT); CREATE INDEX IF NOT EXISTS codex_usage_timestamp ON codex_usage_events(timestamp); CREATE TABLE IF NOT EXISTS cursor_usage_events (id TEXT PRIMARY KEY NOT NULL, workspace_id TEXT NOT NULL, timestamp REAL NOT NULL, input_tokens INTEGER NOT NULL, cache_read_tokens INTEGER NOT NULL, cache_write_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, model TEXT); CREATE INDEX IF NOT EXISTS cursor_usage_timestamp ON cursor_usage_events(timestamp);")
        _ = sqlite3_exec(database, "ALTER TABLE codex_usage_events ADD COLUMN model TEXT;", nil, nil, nil)
    }

    deinit { sqlite3_close(database) }

    nonisolated func upsert(_ events: [CodexUsageEvent]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do { for event in events { try insert(event) }; try execute("COMMIT;") }
        catch { try? execute("ROLLBACK;"); throw error }
    }

    /// The source files are authoritative. Replacing this app-owned projection ensures a parser
    /// correction cannot leave inflated historical rows behind.
    nonisolated func replaceCodex(_ events: [CodexUsageEvent]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute("DELETE FROM codex_usage_events;")
            for event in events { try insert(event) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    nonisolated func today(now: Date, calendar: Calendar = .current) throws -> CodexUsageProjection {
        try codex(range: UsageDateRange(start: calendar.startOfDay(for: now), end: now))
    }

    nonisolated func codex(range: UsageDateRange) throws -> CodexUsageProjection {
        var statement: OpaquePointer?
        let sql = "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(cached_input_tokens),0), COALESCE(SUM(output_tokens),0), MAX(timestamp), COUNT(*) FROM codex_usage_events WHERE timestamp >= ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, range.start.timeIntervalSince1970); sqlite3_bind_double(statement, 2, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let count = Int(sqlite3_column_int64(statement, 4))
        let cutoff: Date? = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        return CodexUsageProjection(inputTokens: Int(sqlite3_column_int64(statement, 0)), cachedInputTokens: Int(sqlite3_column_int64(statement, 1)), outputTokens: Int(sqlite3_column_int64(statement, 2)), cutoff: cutoff, records: count, coverage: count == 0 ? .empty : .available)
    }

    nonisolated func upsertCursor(_ events: [CursorUsageEvent], workspaceID: String) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for event in events {
                var statement: OpaquePointer?
                let sql = "INSERT OR IGNORE INTO cursor_usage_events (id,workspace_id,timestamp,input_tokens,cache_read_tokens,cache_write_tokens,output_tokens,model) VALUES (?,?,?,?,?,?,?,?);"
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.insert }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, event.identifier, -1, SQLITE_TRANSIENT); sqlite3_bind_text(statement, 2, workspaceID, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
                sqlite3_bind_int64(statement, 4, sqlite3_int64(event.inputTokens)); sqlite3_bind_int64(statement, 5, sqlite3_int64(event.cacheReadTokens)); sqlite3_bind_int64(statement, 6, sqlite3_int64(event.cacheWriteTokens)); sqlite3_bind_int64(statement, 7, sqlite3_int64(event.outputTokens)); sqlite3_bind_text(statement, 8, event.model, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.insert }
            }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    nonisolated func cursorToday(workspaceID: String, workspaceName: String, now: Date, calendar: Calendar = .current) throws -> CursorUsageProjection {
        try cursor(workspaceID: workspaceID, workspaceName: workspaceName, range: UsageDateRange(start: calendar.startOfDay(for: now), end: now))
    }

    nonisolated func cursor(workspaceID: String, workspaceName: String, range: UsageDateRange) throws -> CursorUsageProjection {
        var statement: OpaquePointer?
        let sql = "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(cache_read_tokens),0), COALESCE(SUM(cache_write_tokens),0), COALESCE(SUM(output_tokens),0), MAX(timestamp) FROM cursor_usage_events WHERE workspace_id = ? AND timestamp >= ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970); sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let cutoff: Date? = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        return CursorUsageProjection(inputTokens: Int(sqlite3_column_int64(statement, 0)), cacheReadTokens: Int(sqlite3_column_int64(statement, 1)), cacheWriteTokens: Int(sqlite3_column_int64(statement, 2)), outputTokens: Int(sqlite3_column_int64(statement, 3)), cutoff: cutoff, workspaceName: workspaceName, coverage: .available)
    }

    nonisolated func pricingUsage(range: UsageDateRange, workspaceID: String? = nil) throws -> [PricingTokenUsage] {
        var statement: OpaquePointer?
        let table = workspaceID == nil ? "codex_usage_events" : "cursor_usage_events"
        let sql = workspaceID == nil
            ? "SELECT model,input_tokens,cached_input_tokens,0,output_tokens FROM codex_usage_events WHERE timestamp >= ? AND timestamp < ?;"
            : "SELECT model,input_tokens,cache_read_tokens,cache_write_tokens,output_tokens FROM cursor_usage_events WHERE workspace_id = ? AND timestamp >= ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        if let workspaceID { sqlite3_bind_text(statement, index, workspaceID, -1, SQLITE_TRANSIENT); index += 1 }
        sqlite3_bind_double(statement, index, range.start.timeIntervalSince1970); index += 1
        sqlite3_bind_double(statement, index, range.end.timeIntervalSince1970)
        var result: [PricingTokenUsage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let model = sqlite3_column_text(statement, 0).map { String(cString: $0) }
            result.append(PricingTokenUsage(model: model, inputTokens: Int(sqlite3_column_int64(statement, 1)), cacheReadTokens: Int(sqlite3_column_int64(statement, 2)), cacheWriteTokens: Int(sqlite3_column_int64(statement, 3)), outputTokens: Int(sqlite3_column_int64(statement, 4))))
        }
        return result
    }

    private nonisolated func insert(_ event: CodexUsageEvent) throws {
        var statement: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO codex_usage_events (id,timestamp,input_tokens,cached_input_tokens,output_tokens,source_file,model) VALUES (?,?,?,?,?,?,?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.insert }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, event.identifier, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(event.inputTokens)); sqlite3_bind_int64(statement, 4, sqlite3_int64(event.cachedInputTokens)); sqlite3_bind_int64(statement, 5, sqlite3_int64(event.outputTokens)); sqlite3_bind_text(statement, 6, event.sourceFile, -1, SQLITE_TRANSIENT); if let model = event.model { sqlite3_bind_text(statement, 7, model, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(statement, 7) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.insert }
    }

    private nonisolated func execute(_ sql: String) throws { guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw LedgerError.query } }
    private enum LedgerError: Error { case open, query, insert }
}
