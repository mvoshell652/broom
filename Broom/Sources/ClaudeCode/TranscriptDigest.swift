import Foundation

/// Everything Broom keeps from a session transcript. Holds no message bodies beyond the first prompt and a trailing question.
public struct TranscriptDigest: Codable, Equatable, Sendable {
    public var sessionID: String?
    public var cwd: String?
    /// The latest `custom-title` line.
    public var customTitle: String?
    /// The first user prompt, untruncated.
    public var firstPrompt: String?
    /// Timestamp of the first conversation line.
    public var startedAt: Date?
    /// Newest timestamp on any line, including subagent lines.
    public var lastActivityAt: Date?
    public var counts: ActivityCounts
    public var progress: StepProgress?
    public var tail: TranscriptTail
    /// When the user last interrupted a turn, from the interrupt line's own timestamp.
    public var interruptedAt: Date?
    /// Lines that were not valid JSON objects.
    public var malformedLineCount: Int

    public init(
        sessionID: String? = nil,
        cwd: String? = nil,
        customTitle: String? = nil,
        firstPrompt: String? = nil,
        startedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        counts: ActivityCounts = ActivityCounts(),
        progress: StepProgress? = nil,
        tail: TranscriptTail = .other,
        interruptedAt: Date? = nil,
        malformedLineCount: Int = 0
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.customTitle = customTitle
        self.firstPrompt = firstPrompt
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.counts = counts
        self.progress = progress
        self.tail = tail
        self.interruptedAt = interruptedAt
        self.malformedLineCount = malformedLineCount
    }

    /// The session title: the custom title if there is one, else the first prompt cut to 60 characters.
    public var title: String? {
        customTitle ?? firstPrompt.flatMap(LiveSession.title(fromPrompt:))
    }
}
