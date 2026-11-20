import Foundation
import GRDB

/// Broom's SQLite database: the sessions and a little app state. Holds no transcript content.
public struct SessionStore: Sendable {
    private let database: DatabaseQueue

    /// `~/Library/Application Support/Broom/broom.sqlite`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Broom/broom.sqlite")
    }

    /// Opens the database at `url`, creating it and its folder if needed.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(database)
    }

    /// Opens a database that lives in memory, for tests and previews.
    public init() throws {
        database = try DatabaseQueue()
        try Self.migrator.migrate(database)
    }

    // MARK: - Sessions

    /// Returns every saved session. Process ids are not restored: they belong to the previous launch.
    public func loadSessions() async throws -> [LiveSession] {
        try await database.read { db in
            try LiveSession.fetchAll(db).map { session in
                var session = session
                session.pid = nil
                return session
            }
        }
    }

    /// Inserts or updates `sessions`.
    public func save(_ sessions: [LiveSession]) async throws {
        guard !sessions.isEmpty else { return }
        try await database.write { db in
            for session in sessions {
                try session.save(db)
            }
        }
    }

    /// Removes sessions that ended before `date`. Returns how many were removed.
    @discardableResult
    public func deleteSessions(endedBefore date: Date) async throws -> Int {
        try await database.write { db in
            try LiveSession
                .filter(Column("state") == LiveState.ended.rawValue && Column("stateChangedAt") < date)
                .deleteAll(db)
        }
    }

    // MARK: - Hook events

    /// Logs one hook event: which session, which event, and its tool name or notification type.
    ///
    /// The prompt, tool input and tool output are deliberately not kept.
    public func recordHookEvent(_ payload: HookPayload, receivedAt: Date) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO events (sessionID, eventName, detail, processID, receivedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [payload.sessionID, payload.eventName, payload.toolName ?? payload.notificationType, payload.pid, receivedAt]
            )
        }
    }

    /// Removes hook events received before `date`. Returns how many were removed.
    @discardableResult
    public func deleteHookEvents(before date: Date) async throws -> Int {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM events WHERE receivedAt < ?", arguments: [date])
            return db.changesCount
        }
    }

    /// How many hook events are logged.
    public func hookEventCount() async throws -> Int {
        try await database.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
        }
    }

    // MARK: - App state

    /// When the popover last closed, or `nil` if it never has.
    public func lastPopoverOpenedAt() async throws -> Date? {
        try await database.read { db in
            try Double.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?", arguments: [Self.lastPopoverOpenedKey])
                .map(Date.init(timeIntervalSince1970:))
        }
    }

    /// Saves when the popover last closed.
    public func setLastPopoverOpenedAt(_ date: Date) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO app_state (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                arguments: [Self.lastPopoverOpenedKey, date.timeIntervalSince1970]
            )
        }
    }

    /// A saved date under `key`, or `nil` if it was never set.
    public func date(_ key: String) async throws -> Date? {
        try await database.read { db in
            try Double.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?", arguments: [key])
                .map(Date.init(timeIntervalSince1970:))
        }
    }

    /// Saves a date under `key`, replacing any earlier value.
    public func setDate(_ key: String, to date: Date) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO app_state (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                arguments: [key, date.timeIntervalSince1970]
            )
        }
    }

    /// A saved setting, or `nil` if it was never set.
    public func setting(_ key: String) async throws -> String? {
        try await database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_state WHERE key = ?", arguments: ["setting." + key])
        }
    }

    /// Saves a setting under `key`, replacing any earlier value.
    public func setSetting(_ key: String, to value: String) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO app_state (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                arguments: ["setting." + key, value]
            )
        }
    }

    private static let lastPopoverOpenedKey = "lastPopoverOpenedAt"

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "sessions") { table in
                table.primaryKey("id", .text)
                table.column("source", .text).notNull()
                table.column("title", .text).notNull()
                table.column("cwd", .text)
                table.column("repoName", .text)
                table.column("state", .text).notNull().indexed()
                table.column("startedAt", .datetime).notNull()
                table.column("lastActivityAt", .datetime).notNull()
                table.column("stateChangedAt", .datetime).notNull()
                table.column("waitingMessage", .text)
                table.column("progress", .jsonText)
                table.column("userTurns", .integer).notNull()
                table.column("toolCalls", .integer).notNull()
                table.column("pid", .integer)
                table.column("snoozedUntil", .datetime)
                table.column("inferred", .boolean).notNull()
                table.column("hasHookEvents", .boolean).notNull()
                table.column("waitingNotified", .boolean).notNull()
                table.column("hasCustomTitle", .boolean).notNull()
                table.column("transcriptPath", .text)
                table.column("transcriptTail", .jsonText)
                table.column("hookCounts", .jsonText).notNull()
                table.column("transcriptCounts", .jsonText).notNull()
            }
            try db.create(table: "app_state") { table in
                table.primaryKey("key", .text)
                table.column("value", .any)
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "sessions") { table in
                table.add(column: "hookProcessID", .integer)
            }
            try db.create(table: "events") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("sessionID", .text).notNull().indexed()
                table.column("eventName", .text).notNull()
                table.column("detail", .text)
                table.column("processID", .integer)
                table.column("receivedAt", .datetime).notNull().indexed()
            }
        }
        // These two columns were for the 2026-11-18 Inbox and Sweep tabs. Nothing reads or writes them now.
        migrator.registerMigration("v3") { db in
            try db.alter(table: "sessions") { table in
                table.add(column: "handledAt", .datetime)
                table.add(column: "clearedAt", .datetime)
            }
        }
        return migrator
    }
}
