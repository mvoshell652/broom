import Foundation

/// Decides whether a finished session is a quick chat.
public enum QuickChatRule {
    /// A quick chat has at most this many user prompts.
    public static let maximumUserTurns = 2
    /// A quick chat lasts less than this long, from `startedAt` to `lastActivityAt`.
    public static let maximumDuration: TimeInterval = 10 * 60

    /// Whether a session with these totals counts as a quick chat.
    public static func matches(
        userTurns: Int,
        toolCalls: Int,
        startedAt: Date,
        lastActivityAt: Date
    ) -> Bool {
        userTurns <= maximumUserTurns
            && toolCalls == 0
            && lastActivityAt.timeIntervalSince(startedAt) < maximumDuration
    }

    /// Whether `session` counts as a quick chat.
    public static func matches(_ session: LiveSession) -> Bool {
        matches(
            userTurns: session.userTurns,
            toolCalls: session.toolCalls,
            startedAt: session.startedAt,
            lastActivityAt: session.lastActivityAt
        )
    }
}
