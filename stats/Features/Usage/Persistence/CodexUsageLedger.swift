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

enum UsageBucketGranularity: Sendable {
    case hourly
    case daily
}

struct UsageTrendBucket: Sendable, Equatable, Identifiable {
    let start: Date
    let end: Date
    let totalTokens: Int
    let records: Int
    var id: Date { start }
}

struct UsageModelTotal: Sendable, Equatable, Identifiable {
    let model: String
    let totalTokens: Int
    let records: Int
    var id: String { model }
}

enum CursorImportState: String, Sendable {
    case pending, completed, deferred, split
}

struct CursorImportCheckpoint: Sendable, Equatable {
    let range: CursorUsageRange
    let state: CursorImportState
    let retryAfter: Date?
}

enum CursorRangeCoverage: Sendable, Equatable {
    case complete
    case incomplete
}

actor CodexUsageLedger {
    private var database: OpaquePointer?

    /// Shared with `LocalUsageLedger` extensions in the same module.
    var unsafeDatabasePointer: OpaquePointer? { database }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "stats", directoryHint: .isDirectory)) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "usage-ledger.sqlite")
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let opened else { throw LedgerError.open }
        let schema = "CREATE TABLE IF NOT EXISTS codex_usage_events (id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL, input_tokens INTEGER NOT NULL, cached_input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, source_file TEXT NOT NULL, model TEXT); CREATE INDEX IF NOT EXISTS codex_usage_timestamp ON codex_usage_events(timestamp); CREATE TABLE IF NOT EXISTS cursor_usage_events (id TEXT PRIMARY KEY NOT NULL, workspace_id TEXT NOT NULL, timestamp REAL NOT NULL, input_tokens INTEGER NOT NULL, cache_read_tokens INTEGER NOT NULL, cache_write_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, model TEXT); CREATE INDEX IF NOT EXISTS cursor_usage_timestamp ON cursor_usage_events(timestamp); CREATE TABLE IF NOT EXISTS cursor_import_ranges (workspace_id TEXT NOT NULL, start_timestamp REAL NOT NULL, end_timestamp REAL NOT NULL, state TEXT NOT NULL, retry_after REAL, error_message TEXT, updated_at REAL NOT NULL, PRIMARY KEY (workspace_id, start_timestamp, end_timestamp)); CREATE INDEX IF NOT EXISTS cursor_import_ranges_lookup ON cursor_import_ranges(workspace_id, state, start_timestamp, end_timestamp);"
        guard sqlite3_exec(opened, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(opened)
            throw LedgerError.query
        }
        // Older ledgers predate `model` in CREATE TABLE. Add it only when missing so reopen
        // does not log SQLite's duplicate-column error on every launch.
        if !Self.table(opened, "codex_usage_events", hasColumn: "model") {
            guard sqlite3_exec(opened, "ALTER TABLE codex_usage_events ADD COLUMN model TEXT;", nil, nil, nil) == SQLITE_OK else {
                sqlite3_close(opened)
                throw LedgerError.query
            }
        }
        let localSchema = """
            CREATE TABLE IF NOT EXISTS local_usage_events (
                id TEXT PRIMARY KEY NOT NULL,
                provider_kind TEXT NOT NULL,
                timestamp REAL NOT NULL,
                model TEXT NOT NULL,
                underlying_provider TEXT,
                input_tokens INTEGER NOT NULL,
                cached_input_tokens INTEGER NOT NULL,
                cache_creation_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                reasoning_tokens INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS local_usage_provider_timestamp
                ON local_usage_events(provider_kind, timestamp);
            """
        guard sqlite3_exec(opened, localSchema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(opened)
            throw LedgerError.query
        }
        database = opened
    }

    private static func table(_ database: OpaquePointer?, _ table: String, hasColumn column: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1).map({ String(cString: $0) }), name == column {
                return true
            }
        }
        return false
    }

    deinit { sqlite3_close(database) }

    func upsert(_ events: [CodexUsageEvent]) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do { for event in events { try insert(event) }; try execute("COMMIT;") }
        catch { try? execute("ROLLBACK;"); throw error }
    }

    /// The source files are authoritative. Replacing this app-owned projection ensures a parser
    /// correction cannot leave inflated historical rows behind.
    func replaceCodex(_ events: [CodexUsageEvent]) throws {
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

    func today(now: Date, calendar: Calendar = .current) throws -> CodexUsageProjection {
        try codex(range: UsageDateRange(start: calendar.startOfDay(for: now), end: now))
    }

    func codex(range: UsageDateRange) throws -> CodexUsageProjection {
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

    func upsertCursor(_ events: [CursorUsageEvent], workspaceID: String) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for event in events {
                try insertCursor(event, workspaceID: workspaceID)
            }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    func seedCursorImportRanges(_ ranges: [CursorUsageRange], workspaceID: String, now: Date = .now) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for range in ranges { try insertCursorImportRange(range, workspaceID: workspaceID, state: .pending, retryAfter: nil, error: nil, now: now) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    func nextCursorImportRange(workspaceID: String, now: Date = .now) throws -> CursorImportCheckpoint? {
        var statement: OpaquePointer?
        let sql = "SELECT start_timestamp,end_timestamp,state,retry_after FROM cursor_import_ranges WHERE workspace_id = ? AND (state = 'pending' OR (state = 'deferred' AND (retry_after IS NULL OR retry_after <= ?))) ORDER BY end_timestamp DESC LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let rawState = sqlite3_column_text(statement, 2).map({ String(cString: $0) }),
              let state = CursorImportState(rawValue: rawState) else { return nil }
        let retryAfter = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        return CursorImportCheckpoint(range: CursorUsageRange(start: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), end: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))), state: state, retryAfter: retryAfter)
    }

    func completeCursorImport(_ outcome: CursorUsageRangeOutcome, workspaceID: String, range: CursorUsageRange, now: Date = .now) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            if case let .completed(events) = outcome {
                for event in events { try insertCursor(event, workspaceID: workspaceID) }
            }
            try updateCursorImportRange(range, workspaceID: workspaceID, state: .completed, retryAfter: nil, error: nil, now: now)
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    func deferCursorImport(_ range: CursorUsageRange, workspaceID: String, retryAfter: Date?, message: String, now: Date = .now) throws {
        try updateCursorImportRange(range, workspaceID: workspaceID, state: .deferred, retryAfter: retryAfter, error: message, now: now)
    }

    func splitCursorImport(_ range: CursorUsageRange, workspaceID: String, into children: [CursorUsageRange], now: Date = .now) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try updateCursorImportRange(range, workspaceID: workspaceID, state: .split, retryAfter: nil, error: "Range was split after a temporary response failure.", now: now)
            for child in children { try insertCursorImportRange(child, workspaceID: workspaceID, state: .pending, retryAfter: nil, error: nil, now: now) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    func cursorCoverage(workspaceID: String, range: UsageDateRange) throws -> CursorRangeCoverage {
        var statement: OpaquePointer?
        let sql = "SELECT start_timestamp,end_timestamp FROM cursor_import_ranges WHERE workspace_id = ? AND state = 'completed' AND end_timestamp > ? AND start_timestamp < ? ORDER BY start_timestamp ASC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        var cursor = range.start.timeIntervalSince1970
        while sqlite3_step(statement) == SQLITE_ROW {
            let start = sqlite3_column_double(statement, 0), end = sqlite3_column_double(statement, 1)
            if start > cursor { return .incomplete }
            cursor = max(cursor, end)
            if cursor >= range.end.timeIntervalSince1970 {
                return try cursorEventsMateriallyLag(workspaceID: workspaceID, range: range) ? .incomplete : .complete
            }
        }
        return .incomplete
    }

    /// A successful broad request is not complete coverage when it returned records but its
    /// newest record is days behind the requested cutoff. Confirmed empty ranges remain
    /// distinguishable through the source probe rather than being fabricated as activity.
    private func cursorEventsMateriallyLag(workspaceID: String, range: UsageDateRange) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*), MAX(timestamp) FROM cursor_usage_events WHERE workspace_id = ? AND timestamp >= ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let count = sqlite3_column_int64(statement, 0)
        guard count > 0, sqlite3_column_type(statement, 1) != SQLITE_NULL else { return false }
        let latest = sqlite3_column_double(statement, 1)
        return range.end.timeIntervalSince1970 - latest > 60 * 60 * 48
    }

    func pruneCursorHistory(workspaceID: String, before date: Date) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try deleteCursorHistory(table: "cursor_usage_events", workspaceID: workspaceID, date: date, timestampColumn: "timestamp")
            try deleteCursorHistory(table: "cursor_import_ranges", workspaceID: workspaceID, date: date, timestampColumn: "end_timestamp")
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    func cursorToday(workspaceID: String, workspaceName: String, now: Date, calendar: Calendar = .current) throws -> CursorUsageProjection {
        try cursor(workspaceID: workspaceID, workspaceName: workspaceName, range: UsageDateRange(start: calendar.startOfDay(for: now), end: now))
    }

    func cursor(workspaceID: String, workspaceName: String, range: UsageDateRange) throws -> CursorUsageProjection {
        var statement: OpaquePointer?
        let sql = "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(cache_read_tokens),0), COALESCE(SUM(cache_write_tokens),0), COALESCE(SUM(output_tokens),0), MAX(timestamp) FROM cursor_usage_events WHERE workspace_id = ? AND timestamp >= ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970); sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let cutoff: Date? = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        return CursorUsageProjection(inputTokens: Int(sqlite3_column_int64(statement, 0)), cacheReadTokens: Int(sqlite3_column_int64(statement, 1)), cacheWriteTokens: Int(sqlite3_column_int64(statement, 2)), outputTokens: Int(sqlite3_column_int64(statement, 3)), cutoff: cutoff, workspaceName: workspaceName, coverage: cutoff == nil ? .empty : .available)
    }

    func cursorSourceEvidence(workspaceID: String, now: Date = .now, calendar: Calendar = .current) throws -> (windows: [CursorEvidenceWindow], importRanges: [CursorEvidenceImportRange]) {
        let windows = try UsageComparisonPeriod.allCases.map { period -> CursorEvidenceWindow in
            let interval = period.currentInterval(now: now, calendar: calendar)
            let range = UsageDateRange(start: interval.start, end: interval.end)
            let summary = try cursorEvidenceSummary(workspaceID: workspaceID, range: range)
            let coverage = try cursorCoverage(workspaceID: workspaceID, range: range)
            return CursorEvidenceWindow(
                label: period.title, requestedStart: range.start, requestedEnd: range.end,
                eventCount: summary.events, tokenSubtotal: summary.tokens,
                earliestEvent: summary.earliest, latestEvent: summary.latest,
                coverage: coverage == .complete ? "Complete import coverage" : "Import coverage incomplete"
            )
        }

        var statement: OpaquePointer?
        let sql = "SELECT start_timestamp,end_timestamp,state,retry_after,error_message,updated_at FROM cursor_import_ranges WHERE workspace_id = ? ORDER BY end_timestamp DESC;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT)
        var ranges: [CursorEvidenceImportRange] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let retryAfter = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let message = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            guard let state = sqlite3_column_text(statement, 2).map({ String(cString: $0) }) else { continue }
            ranges.append(CursorEvidenceImportRange(
                requestedStart: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                requestedEnd: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                state: state, retryAfter: retryAfter, message: message,
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        return (windows, ranges)
    }

    private func cursorEvidenceSummary(workspaceID: String, range: UsageDateRange) throws -> (events: Int, tokens: Int, earliest: Date?, latest: Date?) {
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*), COALESCE(SUM(input_tokens + cache_read_tokens + cache_write_tokens + output_tokens),0), MIN(timestamp), MAX(timestamp) FROM cursor_usage_events WHERE workspace_id = ? AND timestamp >= ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let earliest = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let latest = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        return (Int(sqlite3_column_int64(statement, 0)), Int(sqlite3_column_int64(statement, 1)), earliest, latest)
    }

    func pricingUsage(range: UsageDateRange, workspaceID: String? = nil) throws -> [PricingTokenUsage] {
        var statement: OpaquePointer?
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

    func trend(range: UsageDateRange, granularity: UsageBucketGranularity, workspaceID: String? = nil, calendar: Calendar = .current) throws -> [UsageTrendBucket] {
        let table = workspaceID == nil ? "codex_usage_events" : "cursor_usage_events"
        let tokenExpression = workspaceID == nil ? "input_tokens + cached_input_tokens + output_tokens" : "input_tokens + cache_read_tokens + cache_write_tokens + output_tokens"
        let scope = workspaceID == nil ? "" : " AND workspace_id = ?"
        let sql = "SELECT timestamp, \(tokenExpression), 1 FROM \(table) WHERE timestamp >= ? AND timestamp < ?\(scope);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, range.end.timeIntervalSince1970)
        if let workspaceID { sqlite3_bind_text(statement, 3, workspaceID, -1, SQLITE_TRANSIENT) }
        var values: [Date: (tokens: Int, records: Int)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            let components: DateComponents
            switch granularity {
            case .hourly: components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            case .daily: components = calendar.dateComponents([.year, .month, .day], from: timestamp)
            }
            guard let bucketStart = calendar.date(from: components) else { continue }
            let current = values[bucketStart] ?? (0, 0)
            values[bucketStart] = (current.tokens + Int(sqlite3_column_int64(statement, 1)), current.records + 1)
        }
        return values.keys.sorted().map { start in
            let end = granularity == .hourly ? calendar.date(byAdding: .hour, value: 1, to: start)! : calendar.date(byAdding: .day, value: 1, to: start)!
            let value = values[start]!
            return UsageTrendBucket(start: start, end: end, totalTokens: value.tokens, records: value.records)
        }
    }

    func modelTotals(range: UsageDateRange, workspaceID: String? = nil) throws -> [UsageModelTotal] {
        let table = workspaceID == nil ? "codex_usage_events" : "cursor_usage_events"
        let tokenExpression = workspaceID == nil ? "input_tokens + cached_input_tokens + output_tokens" : "input_tokens + cache_read_tokens + cache_write_tokens + output_tokens"
        let scope = workspaceID == nil ? "" : " AND workspace_id = ?"
        let sql = "SELECT COALESCE(model, 'Unknown model'), SUM(\(tokenExpression)), COUNT(*) FROM \(table) WHERE timestamp >= ? AND timestamp < ?\(scope) GROUP BY COALESCE(model, 'Unknown model') ORDER BY SUM(\(tokenExpression)) DESC;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, range.end.timeIntervalSince1970)
        if let workspaceID { sqlite3_bind_text(statement, 3, workspaceID, -1, SQLITE_TRANSIENT) }
        var result: [UsageModelTotal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(statement, 0) else { continue }
            result.append(UsageModelTotal(model: String(cString: pointer), totalTokens: Int(sqlite3_column_int64(statement, 1)), records: Int(sqlite3_column_int64(statement, 2))))
        }
        return result
    }

    private func insert(_ event: CodexUsageEvent) throws {
        var statement: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO codex_usage_events (id,timestamp,input_tokens,cached_input_tokens,output_tokens,source_file,model) VALUES (?,?,?,?,?,?,?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.insert }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, event.identifier, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 3, sqlite3_int64(event.inputTokens)); sqlite3_bind_int64(statement, 4, sqlite3_int64(event.cachedInputTokens)); sqlite3_bind_int64(statement, 5, sqlite3_int64(event.outputTokens)); sqlite3_bind_text(statement, 6, event.sourceFile, -1, SQLITE_TRANSIENT); if let model = event.model { sqlite3_bind_text(statement, 7, model, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(statement, 7) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.insert }
    }

    private func insertCursor(_ event: CursorUsageEvent, workspaceID: String) throws {
        var statement: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO cursor_usage_events (id,workspace_id,timestamp,input_tokens,cache_read_tokens,cache_write_tokens,output_tokens,model) VALUES (?,?,?,?,?,?,?,?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.insert }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, event.identifier, -1, SQLITE_TRANSIENT); sqlite3_bind_text(statement, 2, workspaceID, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(event.inputTokens)); sqlite3_bind_int64(statement, 5, sqlite3_int64(event.cacheReadTokens)); sqlite3_bind_int64(statement, 6, sqlite3_int64(event.cacheWriteTokens)); sqlite3_bind_int64(statement, 7, sqlite3_int64(event.outputTokens)); sqlite3_bind_text(statement, 8, event.model, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.insert }
    }

    private func insertCursorImportRange(_ range: CursorUsageRange, workspaceID: String, state: CursorImportState, retryAfter: Date?, error: String?, now: Date) throws {
        var statement: OpaquePointer?
        let sql = "INSERT OR IGNORE INTO cursor_import_ranges (workspace_id,start_timestamp,end_timestamp,state,retry_after,error_message,updated_at) VALUES (?,?,?,?,?,?,?);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.insert }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970); sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970); sqlite3_bind_text(statement, 4, state.rawValue, -1, SQLITE_TRANSIENT)
        if let retryAfter { sqlite3_bind_double(statement, 5, retryAfter.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 5) }
        if let error { sqlite3_bind_text(statement, 6, error, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(statement, 6) }
        sqlite3_bind_double(statement, 7, now.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.insert }
    }

    private func updateCursorImportRange(_ range: CursorUsageRange, workspaceID: String, state: CursorImportState, retryAfter: Date?, error: String?, now: Date) throws {
        var statement: OpaquePointer?
        let sql = "UPDATE cursor_import_ranges SET state = ?, retry_after = ?, error_message = ?, updated_at = ? WHERE workspace_id = ? AND start_timestamp = ? AND end_timestamp = ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, state.rawValue, -1, SQLITE_TRANSIENT)
        if let retryAfter { sqlite3_bind_double(statement, 2, retryAfter.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 2) }
        if let error { sqlite3_bind_text(statement, 3, error, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(statement, 3) }
        sqlite3_bind_double(statement, 4, now.timeIntervalSince1970); sqlite3_bind_text(statement, 5, workspaceID, -1, SQLITE_TRANSIENT); sqlite3_bind_double(statement, 6, range.start.timeIntervalSince1970); sqlite3_bind_double(statement, 7, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw LedgerError.query }
    }

    private func deleteCursorHistory(table: String, workspaceID: String, date: Date, timestampColumn: String) throws {
        var statement: OpaquePointer?
        let sql = "DELETE FROM \(table) WHERE workspace_id = ? AND \(timestampColumn) < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, workspaceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.query }
    }

    private static let localUsageEventsSchema = """
    CREATE TABLE IF NOT EXISTS local_usage_events (
        id TEXT PRIMARY KEY NOT NULL,
        provider_kind TEXT NOT NULL,
        timestamp REAL NOT NULL,
        model TEXT,
        underlying_provider TEXT,
        input_tokens INTEGER NOT NULL,
        cached_input_tokens INTEGER NOT NULL,
        cache_creation_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        reasoning_tokens INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS local_usage_provider_timestamp ON local_usage_events(provider_kind, timestamp);
    """

    private func ensureLocalUsageSchema() throws {
        try execute(Self.localUsageEventsSchema)
    }

    func upsertLocal(_ events: [LocalUsageEvent]) throws {
        try ensureLocalUsageSchema()
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for event in events { try insertLocal(event) }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func replaceLocal(provider: LocalProviderKind, events: [LocalUsageEvent]) throws {
        try ensureLocalUsageSchema()
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            var statement: OpaquePointer?
            let deleteSQL = "DELETE FROM local_usage_events WHERE provider_kind = ?;"
            guard sqlite3_prepare_v2(database, deleteSQL, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
            sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else { sqlite3_finalize(statement); throw LedgerError.query }
            sqlite3_finalize(statement)
            for event in events where event.providerKind == provider {
                try insertLocal(event)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func local(provider: LocalProviderKind, range: UsageDateRange) throws -> LocalUsageProjection {
        try ensureLocalUsageSchema()
        var statement: OpaquePointer?
        let sql = """
        SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(cached_input_tokens),0),
               COALESCE(SUM(cache_creation_tokens),0), COALESCE(SUM(output_tokens),0),
               COALESCE(SUM(reasoning_tokens),0), MAX(timestamp), COUNT(*)
        FROM local_usage_events
        WHERE provider_kind = ? AND timestamp >= ? AND timestamp < ?;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let count = Int(sqlite3_column_int64(statement, 6))
        let cutoff: Date? = sqlite3_column_type(statement, 5) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        return LocalUsageProjection(
            inputTokens: Int(sqlite3_column_int64(statement, 0)),
            cachedInputTokens: Int(sqlite3_column_int64(statement, 1)),
            cacheCreationTokens: Int(sqlite3_column_int64(statement, 2)),
            outputTokens: Int(sqlite3_column_int64(statement, 3)),
            reasoningTokens: Int(sqlite3_column_int64(statement, 4)),
            cutoff: cutoff,
            records: count,
            coverage: count == 0 ? .empty : .available
        )
    }

    func localToday(provider: LocalProviderKind, now: Date, calendar: Calendar = .current) throws -> LocalUsageProjection {
        try local(provider: provider, range: UsageDateRange(start: calendar.startOfDay(for: now), end: now))
    }

    func localSourceEvidence(
        provider: LocalProviderKind,
        requestedWindowLabel: String,
        range: UsageDateRange,
        outcome: LocalSourceOutcome,
        safeErrorReason: String?,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> LocalSourceEvidence {
        let projection = try local(provider: provider, range: range)
        let summary = try localRangeSummary(provider: provider, range: range)
        return LocalSourceEvidence(
            provider: provider,
            requestedWindowLabel: requestedWindowLabel,
            outcome: outcome,
            eventCount: summary.events,
            tokenSubtotal: summary.tokens,
            earliestEvent: summary.earliest,
            latestEvent: summary.latest,
            coverage: projection.coverage,
            safeErrorReason: safeErrorReason
        )
    }

    func pruneLocalHistory(provider: LocalProviderKind, before date: Date) throws {
        try ensureLocalUsageSchema()
        var statement: OpaquePointer?
        let sql = "DELETE FROM local_usage_events WHERE provider_kind = ? AND timestamp < ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.query }
    }

    func localModelTotals(provider: LocalProviderKind, range: UsageDateRange) throws -> [UsageModelTotal] {
        try ensureLocalUsageSchema()
        var statement: OpaquePointer?
        let sql = """
        SELECT COALESCE(model, 'Unknown model'),
               SUM(input_tokens + cached_input_tokens + cache_creation_tokens + output_tokens + reasoning_tokens),
               COUNT(*)
        FROM local_usage_events
        WHERE provider_kind = ? AND timestamp >= ? AND timestamp < ?
        GROUP BY COALESCE(model, 'Unknown model')
        ORDER BY SUM(input_tokens + cached_input_tokens + cache_creation_tokens + output_tokens + reasoning_tokens) DESC;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        var result: [UsageModelTotal] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pointer = sqlite3_column_text(statement, 0) else { continue }
            result.append(
                UsageModelTotal(
                    model: String(cString: pointer),
                    totalTokens: Int(sqlite3_column_int64(statement, 1)),
                    records: Int(sqlite3_column_int64(statement, 2))
                )
            )
        }
        return result
    }

    func localTrend(
        provider: LocalProviderKind,
        range: UsageDateRange,
        granularity: UsageBucketGranularity,
        calendar: Calendar = .current
    ) throws -> [UsageTrendBucket] {
        try ensureLocalUsageSchema()
        let tokenExpression = "input_tokens + cached_input_tokens + cache_creation_tokens + output_tokens + reasoning_tokens"
        let sql = "SELECT timestamp, \(tokenExpression), 1 FROM local_usage_events WHERE provider_kind = ? AND timestamp >= ? AND timestamp < ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        var values: [Date: (tokens: Int, records: Int)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            let components: DateComponents
            switch granularity {
            case .hourly: components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            case .daily: components = calendar.dateComponents([.year, .month, .day], from: timestamp)
            }
            guard let bucketStart = calendar.date(from: components) else { continue }
            let current = values[bucketStart] ?? (0, 0)
            values[bucketStart] = (current.tokens + Int(sqlite3_column_int64(statement, 1)), current.records + 1)
        }
        return values.keys.sorted().map { start in
            let end = granularity == .hourly
                ? calendar.date(byAdding: .hour, value: 1, to: start)!
                : calendar.date(byAdding: .day, value: 1, to: start)!
            let value = values[start]!
            return UsageTrendBucket(start: start, end: end, totalTokens: value.tokens, records: value.records)
        }
    }

    func localPricingUsage(provider: LocalProviderKind, range: UsageDateRange) throws -> [PricingTokenUsage] {
        try ensureLocalUsageSchema()
        var statement: OpaquePointer?
        let sql = """
        SELECT model, input_tokens, cached_input_tokens, cache_creation_tokens, output_tokens
        FROM local_usage_events
        WHERE provider_kind = ? AND timestamp >= ? AND timestamp < ?;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        var result: [PricingTokenUsage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let model = sqlite3_column_text(statement, 0).map { String(cString: $0) }
            result.append(
                PricingTokenUsage(
                    model: model,
                    inputTokens: Int(sqlite3_column_int64(statement, 1)),
                    cacheReadTokens: Int(sqlite3_column_int64(statement, 2)),
                    cacheWriteTokens: Int(sqlite3_column_int64(statement, 3)),
                    outputTokens: Int(sqlite3_column_int64(statement, 4))
                )
            )
        }
        return result
    }

    private func localRangeSummary(provider: LocalProviderKind, range: UsageDateRange) throws -> (events: Int, tokens: Int, earliest: Date?, latest: Date?) {
        var statement: OpaquePointer?
        let sql = """
        SELECT COUNT(*),
               COALESCE(SUM(input_tokens + cached_input_tokens + cache_creation_tokens + output_tokens + reasoning_tokens),0),
               MIN(timestamp), MAX(timestamp)
        FROM local_usage_events
        WHERE provider_kind = ? AND timestamp >= ? AND timestamp < ?;
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.query }
        let earliest = sqlite3_column_type(statement, 2) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let latest = sqlite3_column_type(statement, 3) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        return (
            Int(sqlite3_column_int64(statement, 0)),
            Int(sqlite3_column_int64(statement, 1)),
            earliest,
            latest
        )
    }

    private func insertLocal(_ event: LocalUsageEvent) throws {
        var statement: OpaquePointer?
        let sql = """
        INSERT OR IGNORE INTO local_usage_events
        (id, provider_kind, timestamp, model, underlying_provider, input_tokens, cached_input_tokens, cache_creation_tokens, output_tokens, reasoning_tokens)
        VALUES (?,?,?,?,?,?,?,?,?,?);
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.insert }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, event.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, event.providerKind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
        if let model = event.model {
            sqlite3_bind_text(statement, 4, model, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        if let underlying = event.underlyingProvider {
            sqlite3_bind_text(statement, 5, underlying, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_int64(statement, 6, sqlite3_int64(event.inputTokens))
        sqlite3_bind_int64(statement, 7, sqlite3_int64(event.cachedInputTokens))
        sqlite3_bind_int64(statement, 8, sqlite3_int64(event.cacheCreationTokens))
        sqlite3_bind_int64(statement, 9, sqlite3_int64(event.outputTokens))
        sqlite3_bind_int64(statement, 10, sqlite3_int64(event.reasoningTokens))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.insert }
    }

    func replaceLocal(_ events: [LocalUsageEvent], kind: LocalProviderKind) throws {
        try replaceLocal(provider: kind, events: events)
    }

    func localToday(kind: LocalProviderKind, now: Date, calendar: Calendar = .current) throws -> LocalUsageProjection {
        try localToday(provider: kind, now: now, calendar: calendar)
    }

    func local(kind: LocalProviderKind, range: UsageDateRange) throws -> LocalUsageProjection {
        try local(provider: kind, range: range)
    }

    func localTrend(kind: LocalProviderKind, range: UsageDateRange, granularity: UsageBucketGranularity, calendar: Calendar = .current) throws -> [UsageTrendBucket] {
        try localTrend(provider: kind, range: range, granularity: granularity, calendar: calendar)
    }

    func localModelTotals(kind: LocalProviderKind, range: UsageDateRange) throws -> [UsageModelTotal] {
        try localModelTotals(provider: kind, range: range)
    }

    func localPricingUsage(kind: LocalProviderKind, range: UsageDateRange) throws -> [PricingTokenUsage] {
        try localPricingUsage(provider: kind, range: range)
    }

    func pruneLocalHistory(kind: LocalProviderKind, before date: Date) throws {
        try pruneLocalHistory(provider: kind, before: date)
    }

    func piSourceEvidence(now: Date = .now, calendar: Calendar = .current) throws -> [LocalEvidenceWindow] {
        try UsageComparisonPeriod.allCases.map { period in
            let interval = period.currentInterval(now: now, calendar: calendar)
            let range = UsageDateRange(start: interval.start, end: interval.end)
            let summary = try localRangeSummary(provider: .pi, range: range)
            let underlying = try localUnderlyingProvidersInRange(provider: .pi, range: range)
            return LocalEvidenceWindow(
                label: period.title,
                requestedStart: range.start,
                requestedEnd: range.end,
                eventCount: summary.events,
                tokenSubtotal: summary.tokens,
                earliestEvent: summary.earliest,
                latestEvent: summary.latest,
                underlyingProviders: underlying
            )
        }
    }

    func localUnderlyingProviders(kind: LocalProviderKind) throws -> [String] {
        var statement: OpaquePointer?
        let sql = "SELECT DISTINCT underlying_provider FROM local_usage_events WHERE provider_kind = ? AND underlying_provider IS NOT NULL ORDER BY underlying_provider;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        var providers: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0) {
                providers.append(String(cString: pointer))
            }
        }
        return providers
    }

    func localUnderlyingProviders(provider: LocalProviderKind, range: UsageDateRange) throws -> [String] {
        try localUnderlyingProvidersInRange(provider: provider, range: range)
    }

    private func localUnderlyingProvidersInRange(provider: LocalProviderKind, range: UsageDateRange) throws -> [String] {
        var statement: OpaquePointer?
        let sql = "SELECT DISTINCT underlying_provider FROM local_usage_events WHERE provider_kind = ? AND timestamp >= ? AND timestamp < ? AND underlying_provider IS NOT NULL ORDER BY underlying_provider;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.query }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, range.end.timeIntervalSince1970)
        var providers: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0) {
                providers.append(String(cString: pointer))
            }
        }
        return providers
    }

    private func execute(_ sql: String) throws { guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw LedgerError.query } }
    private enum LedgerError: Error { case open, query, insert }
}
