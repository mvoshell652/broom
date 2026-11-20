import Foundation

/// One tracked session and everything the Live view shows for it.
public struct LiveSession: Identifiable, Codable, Equatable, Sendable {
    /// Claude Code `session_id`.
    public let id: String
    /// Which kind of source reported the session.
    public var source: SessionSourceKind
    /// The session's title: a custom or generated one, else the first prompt shortened.
    public var title: String
    /// Project path for Code sessions.
    public var cwd: String?
    /// Last path component of `cwd`.
    public var repoName: String?
    public var state: LiveState
    /// When the session began: its first event, or the transcript's first line if that is earlier.
    public var startedAt: Date
    /// The latest sign of life from hooks or the transcript. Orders rows, and is not reset by a state change.
    public var lastActivityAt: Date
    /// When `state` last changed. Waiting and done rows age from here, not from `lastActivityAt`.
    public var stateChangedAt: Date
    /// From a `Notification` or `PermissionRequest` hook, or the last assistant question.
    public var waitingMessage: String?
    /// The step counts from the session's task list, or `nil` when it has none.
    public var progress: StepProgress?
    /// User prompts so far: the larger of what hooks and the transcript report.
    public var userTurns: Int
    /// Tool calls so far: the larger of what hooks and the transcript report.
    public var toolCalls: Int
    /// The Claude Code process id while that process is running, otherwise `nil`. It is never restored from the database.
    public var pid: Int32?
    /// While this is in the future the session is hidden from Waiting and does not notify. `nil` when not snoozed.
    public var snoozedUntil: Date?
    /// The process a hook last reported for this session. It may no longer be running; `pid` is set only while it is.
    public var hookProcessID: Int32?

    /// Whether `state` was inferred from the transcript instead of reported by a hook.
    public var isInferred: Bool
    /// Whether any hook event has been seen. Once true, the transcript only enriches.
    public var hasHookEvents: Bool
    /// Whether the waiting notification was already requested for the current wait.
    public var hasNotifiedWaiting: Bool
    /// Whether `title` came from a user or generated session title instead of the first prompt.
    public var hasCustomTitle: Bool
    /// The transcript file's path, once known.
    public var transcriptPath: String?
    /// What the end of the transcript shows, used to infer a wait when no hook says so.
    public var transcriptTail: TranscriptTail?
    /// Turns and tool calls reported by hooks since Broom first saw the session.
    public var hookCounts: ActivityCounts
    /// Turns and tool calls found in the transcript.
    public var transcriptCounts: ActivityCounts

    /// Keeps the stored names of the two renamed flags, so databases and JSON written earlier still decode.
    private enum CodingKeys: String, CodingKey {
        case id, source, title, cwd, repoName, state, startedAt, lastActivityAt, stateChangedAt, waitingMessage
        case progress, userTurns, toolCalls, pid, snoozedUntil, hookProcessID
        case isInferred = "inferred"
        case hasHookEvents
        case hasNotifiedWaiting = "waitingNotified"
        case hasCustomTitle, transcriptPath, transcriptTail, hookCounts, transcriptCounts
    }

    public init(
        id: String,
        source: SessionSourceKind = .claudeCode,
        title: String = "",
        cwd: String? = nil,
        state: LiveState,
        startedAt: Date,
        lastActivityAt: Date,
        stateChangedAt: Date,
        waitingMessage: String? = nil,
        progress: StepProgress? = nil,
        userTurns: Int = 0,
        toolCalls: Int = 0,
        pid: Int32? = nil,
        snoozedUntil: Date? = nil,
        isInferred: Bool = false,
        hasHookEvents: Bool = false,
        hasNotifiedWaiting: Bool = false,
        hasCustomTitle: Bool = false,
        transcriptPath: String? = nil,
        transcriptTail: TranscriptTail? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.cwd = cwd
        self.repoName = cwd.flatMap(Self.repoName(forWorkingDirectory:))
        self.state = state
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.stateChangedAt = stateChangedAt
        self.waitingMessage = waitingMessage
        self.progress = progress
        self.userTurns = userTurns
        self.toolCalls = toolCalls
        self.pid = pid
        self.snoozedUntil = snoozedUntil
        self.isInferred = isInferred
        self.hasHookEvents = hasHookEvents
        self.hasNotifiedWaiting = hasNotifiedWaiting
        self.hasCustomTitle = hasCustomTitle
        self.transcriptPath = transcriptPath
        self.transcriptTail = transcriptTail
        self.hookCounts = ActivityCounts(userTurns: userTurns, toolCalls: toolCalls)
        self.transcriptCounts = ActivityCounts()
    }

    /// Whether the session is snoozed at `date`.
    public func isSnoozed(at date: Date) -> Bool {
        snoozedUntil.map { $0 > date } ?? false
    }

    /// Sets `cwd` and derives `repoName` from it.
    public mutating func setWorkingDirectory(_ path: String) {
        cwd = path
        repoName = Self.repoName(forWorkingDirectory: path)
    }

    /// Recomputes `userTurns` and `toolCalls` as the larger of what hooks and the transcript report.
    ///
    /// Hooks arrive first but miss anything from before Broom launched; the transcript is complete but lags.
    public mutating func refreshCounts() {
        userTurns = max(hookCounts.userTurns, transcriptCounts.userTurns)
        toolCalls = max(hookCounts.toolCalls, transcriptCounts.toolCalls)
    }

    /// The title for a session whose first prompt is `prompt`: whitespace collapsed, at most 60 characters.
    public static func title(fromPrompt prompt: String) -> String? {
        let collapsed = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maximumPromptTitleLength else { return collapsed }
        return collapsed.prefix(maximumPromptTitleLength - 1) + "…"
    }

    public static let maximumPromptTitleLength = 60

    private static func repoName(forWorkingDirectory path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
