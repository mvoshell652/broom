import Foundation
import GRDB

/// How the user has organised their chats: workstreams and the project folders each owns, chats filed by hand,
/// chats merged or archived, pairs marked as not duplicates, open loops marked done, sweep cards skipped, and a log of
/// those changes for undoing them.
///
/// A separate file from the chat index, which can be deleted and rebuilt; this cannot be rebuilt.
public struct WorkstreamStore: Sendable {
    private let database: DatabaseQueue

    /// Opens the store at `url`, creating it and its folder if needed.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(database)
    }

    /// Opens a store that lives in memory, for tests and previews.
    public init() throws {
        database = try DatabaseQueue()
        try Self.migrator.migrate(database)
    }

    // MARK: - Reading

    /// Every workstream, oldest first.
    public func workstreams() throws -> [Workstream] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM workstreams ORDER BY id").map { Workstream(id: $0["id"], name: $0["name"]) }
        }
    }

    /// The workstream that owns each project folder, by folder path.
    public func folderOwners() throws -> [String: Int64] {
        try pairs(sql: "SELECT path, workstreamID FROM folders")
    }

    /// The workstream each chat was filed in by hand, by chat id. This wins over the chat's folder.
    public func filedChats() throws -> [String: Int64] {
        try pairs(sql: "SELECT chatID, workstreamID FROM chats")
    }

    /// The merge group of every merged chat, by chat id. Chats with the same group are one stack.
    public func mergeGroups() throws -> [String: String] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT chatID, groupID FROM merges").reduce(into: [String: String]()) { $0[$1[0]] = $1[1] }
        }
    }

    /// Pairs of chats the user said are not the same conversation.
    public func distinctPairs() throws -> Set<ChatPair> {
        try database.read { db in
            Set(try Row.fetchAll(db, sql: "SELECT first, second FROM distinctPairs").map { ChatPair($0[0], $0[1]) })
        }
    }

    /// When each open loop was marked done, by chat id.
    public func closedLoops() throws -> [String: Date] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT chatID, closedAt FROM closedLoops").reduce(into: [String: Date]()) { $0[$1[0]] = $1[1] }
        }
    }

    /// When each archived chat was archived, by chat id.
    public func archivedChats() throws -> [String: Date] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT chatID, archivedAt FROM archived").reduce(into: [String: Date]()) { $0[$1[0]] = $1[1] }
        }
    }

    /// The sweep cards skipped and not yet due back as of `date`, by card id.
    public func skippedCards(at date: Date) throws -> Set<String> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT cardID FROM sweepSkips WHERE until > ?", arguments: [date]))
        }
    }

    /// When a sweep was last finished.
    public func lastSweptAt() throws -> Date? {
        try database.read { db in try Date.fetchOne(db, sql: "SELECT value FROM state WHERE key = ?", arguments: [Self.lastSweptKey]) }
    }

    /// The recorded changes made since `date`, newest first.
    public func log(since date: Date) throws -> [OrganizerLogEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, summary, change, at FROM log WHERE at >= ? ORDER BY id DESC", arguments: [date]).compactMap { row in
                guard let change = try? JSONDecoder().decode(OrganizerChange.self, from: row["change"] as Data) else { return nil }
                return OrganizerLogEntry(id: row["id"], summary: row["summary"], change: change, date: row["at"])
            }
        }
    }

    /// Whether workstreams have been made from the project folders yet.
    public func isSeeded() throws -> Bool {
        try database.read { db in try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM state WHERE key = ?)", arguments: [Self.seededKey]) ?? false }
    }

    // MARK: - Writing

    /// Makes one workstream per project folder, named after it, the first time it is called. Later calls do nothing.
    ///
    /// - Returns: Whether this call did the seeding.
    @discardableResult
    public func seed(folders: [String], at date: Date = Date()) throws -> Bool {
        try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT NOT EXISTS (SELECT 1 FROM state WHERE key = ?)", arguments: [Self.seededKey]) ?? false else { return false }
            for folder in folders.sorted() {
                try Self.insert(name: ProjectFolder.name(of: folder), folders: [folder], into: db)
            }
            try db.execute(sql: "INSERT INTO state (key, value) VALUES (?, ?)", arguments: [Self.seededKey, date])
            return true
        }
    }

    /// Makes a workstream that owns `folders`. A folder another workstream owned moves to this one.
    @discardableResult
    public func create(name: String, folders: [String] = []) throws -> Workstream {
        try database.write { db in try Self.insert(name: name, folders: folders, into: db) }
    }

    /// Renames a workstream. A blank name is ignored.
    public func rename(_ id: Int64, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try database.write { db in
            try db.execute(sql: "UPDATE workstreams SET name = ? WHERE id = ?", arguments: [trimmed, id])
        }
    }

    /// Files one chat in a workstream, whatever folder it ran in.
    public func file(chatID: String, in workstreamID: Int64) throws {
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO chats (chatID, workstreamID) VALUES (?, ?) ON CONFLICT (chatID) DO UPDATE SET workstreamID = excluded.workstreamID",
                arguments: [chatID, workstreamID]
            )
        }
    }

    /// Merges chats into one stack. Stacks any of them were already in are joined to it. Nothing is deleted.
    ///
    /// - Returns: Every chat now in the stack with the merge group it was in before, if any, for undoing the merge.
    @discardableResult
    public func merge(chatIDs: [String]) throws -> [String: String?] {
        guard chatIDs.count > 1 else { return [:] }
        return try database.write { db in
            var previous: [String: String?] = [:]
            let group = UUID().uuidString
            for id in chatIDs where previous[id] == nil {
                if let existing = try String.fetchOne(db, sql: "SELECT groupID FROM merges WHERE chatID = ?", arguments: [id]) {
                    for member in try String.fetchAll(db, sql: "SELECT chatID FROM merges WHERE groupID = ?", arguments: [existing]) {
                        previous[member] = .some(existing)
                    }
                    try db.execute(sql: "UPDATE merges SET groupID = ? WHERE groupID = ?", arguments: [group, existing])
                } else {
                    previous[id] = .some(nil)
                    try db.execute(sql: "INSERT INTO merges (chatID, groupID) VALUES (?, ?)", arguments: [id, group])
                }
            }
            return previous
        }
    }

    /// Puts chats back in the merge groups they were in before a merge.
    public func restoreMergeGroups(_ groups: [String: String?]) throws {
        try database.write { db in
            for (id, group) in groups {
                if let group {
                    try db.execute(sql: "UPDATE merges SET groupID = ? WHERE chatID = ?", arguments: [group, id])
                } else {
                    try db.execute(sql: "DELETE FROM merges WHERE chatID = ?", arguments: [id])
                }
            }
        }
    }

    /// Takes apart the stack that `chatID` is in.
    public func unmerge(stackContaining chatID: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM merges WHERE groupID = (SELECT groupID FROM merges WHERE chatID = ?)", arguments: [chatID])
        }
    }

    /// Records that none of these chats is a duplicate of another, so they are not suggested together again.
    public func markDistinct(chatIDs: [String]) throws {
        try database.write { db in
            for (index, first) in chatIDs.enumerated() {
                for second in chatIDs[(index + 1)...] {
                    let pair = ChatPair(first, second)
                    try db.execute(sql: "INSERT OR IGNORE INTO distinctPairs (first, second) VALUES (?, ?)", arguments: [pair.first, pair.second])
                }
            }
        }
    }

    /// Forgets that these chats were marked as not duplicates of each other.
    public func unmarkDistinct(chatIDs: [String]) throws {
        try database.write { db in
            for (index, first) in chatIDs.enumerated() {
                for second in chatIDs[(index + 1)...] {
                    let pair = ChatPair(first, second)
                    try db.execute(sql: "DELETE FROM distinctPairs WHERE first = ? AND second = ?", arguments: [pair.first, pair.second])
                }
            }
        }
    }

    /// Takes a chat out of the workstream it was filed in by hand, leaving it to its folder.
    public func unfile(chatID: String) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM chats WHERE chatID = ?", arguments: [chatID]) }
    }

    /// Deletes a workstream. The folders it owned and the chats filed in it go back to being unsorted.
    public func deleteWorkstream(_ id: Int64) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM workstreams WHERE id = ?", arguments: [id]) }
    }

    /// Archives chats as of `date`. A chat that is active after that is no longer archived.
    public func archive(chatIDs: [String], at date: Date = Date()) throws {
        try database.write { db in
            for id in chatIDs {
                try db.execute(
                    sql: "INSERT INTO archived (chatID, archivedAt) VALUES (?, ?) ON CONFLICT (chatID) DO UPDATE SET archivedAt = excluded.archivedAt",
                    arguments: [id, date]
                )
            }
        }
    }

    public func unarchive(chatIDs: [String]) throws {
        try database.write { db in
            for id in chatIDs { try db.execute(sql: "DELETE FROM archived WHERE chatID = ?", arguments: [id]) }
        }
    }

    /// Reopens a loop, or puts back the earlier time it was marked done.
    public func reopenLoop(chatID: String, previouslyClosedAt: Date?) throws {
        if let previouslyClosedAt {
            try closeLoop(chatID: chatID, at: previouslyClosedAt)
        } else {
            try database.write { db in try db.execute(sql: "DELETE FROM closedLoops WHERE chatID = ?", arguments: [chatID]) }
        }
    }

    /// Keeps a sweep card out of the sweep until `date`.
    public func skipCard(id: String, until date: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO sweepSkips (cardID, until) VALUES (?, ?) ON CONFLICT (cardID) DO UPDATE SET until = excluded.until",
                arguments: [id, date]
            )
        }
    }

    /// Records that a sweep was finished at `date`.
    public func setLastSwept(at date: Date) throws {
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO state (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                arguments: [Self.lastSweptKey, date]
            )
        }
    }

    /// Records a change so it can be undone, and forgets changes from before `horizon`.
    public func record(_ change: OrganizerChange, summary: String, at date: Date, forgettingBefore horizon: Date) throws {
        let data = try JSONEncoder().encode(change)
        try database.write { db in
            try db.execute(sql: "INSERT INTO log (summary, change, at) VALUES (?, ?, ?)", arguments: [summary, data, date])
            try db.execute(sql: "DELETE FROM log WHERE at < ?", arguments: [horizon])
        }
    }

    /// Removes a recorded change from the log, once it has been undone.
    public func removeLogEntry(_ id: Int64) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM log WHERE id = ?", arguments: [id]) }
    }

    /// Marks a chat's open loop done as of `date`.
    public func closeLoop(chatID: String, at date: Date = Date()) throws {
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO closedLoops (chatID, closedAt) VALUES (?, ?) ON CONFLICT (chatID) DO UPDATE SET closedAt = excluded.closedAt",
                arguments: [chatID, date]
            )
        }
    }

    private static func insert(name: String, folders: [String], into db: Database) throws -> Workstream {
        try db.execute(sql: "INSERT INTO workstreams (name) VALUES (?)", arguments: [name])
        let id = db.lastInsertedRowID
        for folder in folders {
            try db.execute(
                sql: "INSERT INTO folders (path, workstreamID) VALUES (?, ?) ON CONFLICT (path) DO UPDATE SET workstreamID = excluded.workstreamID",
                arguments: [folder, id]
            )
        }
        return Workstream(id: id, name: name)
    }

    private func pairs(sql: String) throws -> [String: Int64] {
        try database.read { db in
            try Row.fetchAll(db, sql: sql).reduce(into: [String: Int64]()) { $0[$1[0]] = $1[1] }
        }
    }

    private static let seededKey = "seededAt"
    private static let lastSweptKey = "lastSweptAt"

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "workstreams") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
            }
            try db.create(table: "folders") { table in
                table.primaryKey("path", .text)
                table.column("workstreamID", .integer).notNull().indexed().references("workstreams", onDelete: .cascade)
            }
            try db.create(table: "chats") { table in
                table.primaryKey("chatID", .text)
                table.column("workstreamID", .integer).notNull().indexed().references("workstreams", onDelete: .cascade)
            }
            try db.create(table: "state") { table in
                table.primaryKey("key", .text)
                table.column("value", .datetime)
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "merges") { table in
                table.primaryKey("chatID", .text)
                table.column("groupID", .text).notNull().indexed()
            }
            try db.create(table: "distinctPairs") { table in
                table.column("first", .text).notNull()
                table.column("second", .text).notNull()
                table.primaryKey(["first", "second"])
            }
            try db.create(table: "closedLoops") { table in
                table.primaryKey("chatID", .text)
                table.column("closedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v3") { db in
            try db.create(table: "archived") { table in
                table.primaryKey("chatID", .text)
                table.column("archivedAt", .datetime).notNull()
            }
            try db.create(table: "sweepSkips") { table in
                table.primaryKey("cardID", .text)
                table.column("until", .datetime).notNull()
            }
            try db.create(table: "log") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("summary", .text).notNull()
                table.column("change", .blob).notNull()
                table.column("at", .datetime).notNull().indexed()
            }
        }
        return migrator
    }
}
