import Foundation

/// One chat in the index: what search and the Inbox need to list it. Its text lives in the full-text table.
public struct IndexedChat: Identifiable, Equatable, Sendable {
    /// Claude Code `session_id`.
    public let id: String
    /// The chat's own title, or its first prompt shortened when it has none.
    public var title: String
    /// Whether `title` was set by the user or Claude Code, and not taken from the first prompt.
    public var hasCustomTitle: Bool
    /// The folder the chat ran in.
    public var cwd: String?
    /// The first thing the user typed.
    public var firstPrompt: String?
    /// The last thing said in the chat, and who said it. Open loops are found from these.
    public var lastTurnText: String?
    public var lastTurnRole: ChatRole?
    public var startedAt: Date?
    public var lastActivityAt: Date?
    /// How many prompts and replies are indexed.
    public var turnCount: Int
    public var transcriptPath: String

    public init(id: String, title: String = "", hasCustomTitle: Bool = false, cwd: String? = nil, firstPrompt: String? = nil,
                lastTurnText: String? = nil, lastTurnRole: ChatRole? = nil, startedAt: Date? = nil, lastActivityAt: Date? = nil,
                turnCount: Int = 0, transcriptPath: String) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.cwd = cwd
        self.firstPrompt = firstPrompt
        self.lastTurnText = lastTurnText
        self.lastTurnRole = lastTurnRole
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.turnCount = turnCount
        self.transcriptPath = transcriptPath
    }

    /// The last path component of `cwd`.
    public var repoName: String? {
        cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty || $0 == "/" ? nil : $0 }
    }

    /// Adds what a newly read stretch of the transcript contained.
    public mutating func merge(_ batch: TranscriptTextBatch) {
        if let cwd = batch.cwd { self.cwd = cwd }
        if let customTitle = batch.customTitle {
            title = customTitle
            hasCustomTitle = true
        }
        for turn in batch.turns {
            if turn.role == .user, firstPrompt == nil {
                firstPrompt = turn.text
                if !hasCustomTitle { title = LiveSession.title(fromPrompt: turn.text) ?? title }
            }
            if let date = turn.date {
                startedAt = min(startedAt ?? date, date)
                lastActivityAt = max(lastActivityAt ?? date, date)
            }
        }
        if let last = batch.turns.last {
            lastTurnText = last.text
            lastTurnRole = last.role
        }
        turnCount += batch.turns.count
    }

    /// The text a chat is compared by: its title and how it began.
    public var embeddingText: String {
        [hasCustomTitle ? title : nil, firstPrompt.map { String($0.prefix(600)) }].compactMap { $0 }.joined(separator: ". ")
    }
}
