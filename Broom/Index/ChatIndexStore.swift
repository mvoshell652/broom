import Foundation
import GRDB

/// The chat index: every Claude Code chat's title, its prompts and replies for full-text search, and a vector for
/// comparing chats by meaning. It is a separate file from Broom's session database, so it can be deleted on its own.
///
/// This is the one place Broom keeps conversation text. Tool input and output are never stored.
public struct ChatIndexStore: Sendable {
    private let database: DatabaseQueue

    /// `~/Library/Application Support/Broom/index.sqlite`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Broom/index.sqlite")
    }

    /// Opens the index at `url`, creating it and its folder if needed.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(database)
        // It holds conversation text, so only the user may read it, wherever the file was put.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Opens an index that lives in memory, for tests.
    public init() throws {
        database = try DatabaseQueue()
        try Self.migrator.migrate(database)
    }

    // MARK: - Writing

    /// How far into the transcript at `path` has been indexed, and the file it was when that was recorded.
    public func progress(forPath path: String) throws -> (fileNumber: UInt64, offset: UInt64)? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT fileNumber, offset FROM files WHERE path = ?", arguments: [path])
                .map { (UInt64($0["fileNumber"] as Int64), UInt64($0["offset"] as Int64)) }
        }
    }

    /// How far every transcript has been read, by path. One query, for a pass over all of them.
    public func allProgress() throws -> [String: (fileNumber: UInt64, offset: UInt64)] {
        try database.read { db in
            var progress: [String: (fileNumber: UInt64, offset: UInt64)] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT path, fileNumber, offset FROM files") {
                progress[row["path"]] = (UInt64(row["fileNumber"] as Int64), UInt64(row["offset"] as Int64))
            }
            return progress
        }
    }

    /// Saves a chat, the turns newly read for it, and how far its transcript has now been read, in one transaction.
    public func save(_ chat: IndexedChat, adding turns: [ChatTurn], fileNumber: UInt64, offset: UInt64) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO chats (id, title, hasCustomTitle, cwd, firstPrompt, lastTurnText, lastTurnRole, startedAt, lastActivityAt, turnCount, transcriptPath)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (id) DO UPDATE SET title = excluded.title, hasCustomTitle = excluded.hasCustomTitle, cwd = excluded.cwd,
                        firstPrompt = excluded.firstPrompt, lastTurnText = excluded.lastTurnText, lastTurnRole = excluded.lastTurnRole,
                        startedAt = excluded.startedAt, lastActivityAt = excluded.lastActivityAt, turnCount = excluded.turnCount,
                        transcriptPath = excluded.transcriptPath
                    """,
                arguments: [chat.id, chat.title, chat.hasCustomTitle, chat.cwd, chat.firstPrompt, chat.lastTurnText, chat.lastTurnRole?.rawValue,
                            chat.startedAt, chat.lastActivityAt, chat.turnCount, chat.transcriptPath]
            )
            for turn in turns {
                try db.execute(sql: "INSERT INTO turns (chatID, role, text) VALUES (?, ?, ?)", arguments: [chat.id, turn.role.rawValue, turn.text])
            }
            // The title is searchable too. It can change, so its row is replaced on every save.
            try db.execute(sql: "DELETE FROM turns WHERE chatID = ? AND role = ?", arguments: [chat.id, Self.titleRole])
            if !chat.title.isEmpty {
                try db.execute(sql: "INSERT INTO turns (chatID, role, text) VALUES (?, ?, ?)", arguments: [chat.id, Self.titleRole, chat.title])
            }
            try db.execute(
                sql: "INSERT INTO files (path, fileNumber, offset) VALUES (?, ?, ?) ON CONFLICT (path) DO UPDATE SET fileNumber = excluded.fileNumber, offset = excluded.offset",
                arguments: [chat.transcriptPath, Int64(fileNumber), Int64(offset)]
            )
        }
    }

    /// Forgets a chat entirely, for when its transcript was replaced or truncated and must be read again.
    public func removeChat(id: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM turns WHERE chatID = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM embeddings WHERE chatID = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM chats WHERE id = ?", arguments: [id])
        }
    }

    /// Saves the vector a chat is compared by, with the text it was made from.
    public func saveEmbedding(_ vector: [Float], of text: String, forChat id: String) throws {
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO embeddings (chatID, vector, source) VALUES (?, ?, ?) ON CONFLICT (chatID) DO UPDATE SET vector = excluded.vector, source = excluded.source",
                arguments: [id, VectorMath.data(from: vector), text]
            )
        }
    }

    /// Deletes everything in the index.
    public func removeAll() throws {
        try database.write { db in
            for table in ["turns", "embeddings", "chats", "files"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    // MARK: - Reading

    /// The chat with this id, if it is indexed.
    public func chat(id: String) throws -> IndexedChat? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM chats WHERE id = ?", arguments: [id]).map(Self.chat(from:))
        }
    }

    /// Every indexed chat, most recently active first.
    public func allChats() throws -> [IndexedChat] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM chats ORDER BY lastActivityAt DESC, id").map(Self.chat(from:))
        }
    }

    /// How many chats are indexed.
    public func chatCount() throws -> Int {
        try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chats") ?? 0 }
    }

    /// Chats whose comparison text has changed since their vector was made, or that have none yet.
    public func chatsNeedingEmbedding() throws -> [IndexedChat] {
        let chats = try allChats()
        let sources = try database.read { db in
            try Row.fetchAll(db, sql: "SELECT chatID, source FROM embeddings").reduce(into: [String: String]()) { $0[$1["chatID"]] = $1["source"] }
        }
        return chats.filter { !$0.embeddingText.isEmpty && sources[$0.id] != $0.embeddingText }
    }

    /// The text each of these chats' vectors was made from, by chat id.
    public func embeddingSources(forChats ids: [String]) throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        return try database.read { db in
            var sources: [String: String] = [:]
            for id in ids {
                if let source = try String.fetchOne(db, sql: "SELECT source FROM embeddings WHERE chatID = ?", arguments: [id]) {
                    sources[id] = source
                }
            }
            return sources
        }
    }

    /// Every stored vector by chat id.
    public func embeddings() throws -> [String: [Float]] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT chatID, vector FROM embeddings").reduce(into: [String: [Float]]()) {
                $0[$1["chatID"]] = VectorMath.vector(from: $1["vector"])
            }
        }
    }

    /// Chats containing the query's words, best match first, each with the passage that matched.
    ///
    /// The passage is `nil` when only the chat's title matched, since the title is shown anyway.
    public func textMatches(for query: String, limit: Int) throws -> [(chatID: String, snippet: String?)] {
        guard let pattern = FTS5Pattern(matchingAnyTokenIn: query) else { return [] }
        return try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT chatID, role, snippet(turns, 2, '', '', '…', 16) AS passage FROM turns WHERE turns MATCH ? ORDER BY bm25(turns) LIMIT ?",
                arguments: [pattern, limit * 8]
            )
            // Several rows of one chat can match. The chat ranks by its best row and shows its best passage from the conversation.
            var order: [String] = []
            var passages: [String: String] = [:]
            for row in rows {
                let id: String = row["chatID"]
                if !order.contains(id) { order.append(id) }
                if passages[id] == nil, (row["role"] as String) != Self.titleRole { passages[id] = row["passage"] }
            }
            return order.prefix(limit).map { ($0, passages[$0]) }
        }
    }

    private static func chat(from row: Row) -> IndexedChat {
        IndexedChat(
            id: row["id"], title: row["title"], hasCustomTitle: row["hasCustomTitle"], cwd: row["cwd"], firstPrompt: row["firstPrompt"],
            lastTurnText: row["lastTurnText"], lastTurnRole: (row["lastTurnRole"] as String?).flatMap(ChatRole.init(rawValue:)),
            startedAt: row["startedAt"], lastActivityAt: row["lastActivityAt"], turnCount: row["turnCount"], transcriptPath: row["transcriptPath"]
        )
    }

    /// The role of the full-text row that holds a chat's title.
    private static let titleRole = "title"

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "chats") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("hasCustomTitle", .boolean).notNull()
                table.column("cwd", .text)
                table.column("firstPrompt", .text)
                table.column("lastTurnText", .text)
                table.column("lastTurnRole", .text)
                table.column("startedAt", .datetime)
                table.column("lastActivityAt", .datetime).indexed()
                table.column("turnCount", .integer).notNull()
                table.column("transcriptPath", .text).notNull()
            }
            try db.create(virtualTable: "turns", using: FTS5()) { table in
                table.tokenizer = .porter(wrapping: .unicode61())
                table.column("chatID").notIndexed()
                table.column("role").notIndexed()
                table.column("text")
            }
            try db.create(table: "embeddings") { table in
                table.primaryKey("chatID", .text)
                table.column("vector", .blob).notNull()
                table.column("source", .text).notNull()
            }
            try db.create(table: "files") { table in
                table.primaryKey("path", .text)
                table.column("fileNumber", .integer).notNull()
                table.column("offset", .integer).notNull()
            }
        }
        return migrator
    }
}
