import Foundation

/// Finds chats that were left with something still to do.
public enum OpenLoopFinder {
    /// How `chat` was left open as of `now`, or `nil` if it was not.
    ///
    /// A chat is an open loop when it has been quiet for a day but not yet a month, and it ended on a question from
    /// Claude or on the user putting the work off. A chat still active today is not a loop yet, and after a month it
    /// is history.
    ///
    /// - Parameter closedAt: When the user marked this chat's loop done. Activity after that opens it again.
    public static func kind(of chat: IndexedChat, closedAt: Date? = nil, now: Date) -> OpenLoopKind? {
        guard let lastActivityAt = chat.lastActivityAt else { return nil }
        let quiet = now.timeIntervalSince(lastActivityAt)
        guard quiet >= minimumQuiet, quiet <= maximumQuiet else { return nil }
        if let closedAt, closedAt >= lastActivityAt { return nil }
        return ending(of: chat)
    }

    /// How `chat` ended, if it ended with something still to do, however long ago that was.
    public static func ending(of chat: IndexedChat) -> OpenLoopKind? {
        guard let role = chat.lastTurnRole,
              let text = chat.lastTurnText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        switch role {
        case .assistant:
            return text.hasSuffix("?") ? .question : nil
        case .user:
            // Putting work off is a short remark. A long message that happens to contain "later" is not one, and
            // neither is the summary Claude Code writes when it continues a long chat.
            guard text.count <= maximumDeferralLength, TranscriptTextReader.isConversation(text) else { return nil }
            let lowercased = text.lowercased()
            guard deferrals.contains(where: lowercased.contains) else { return nil }
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return .deferred(line.count > quoteLength ? line.prefix(quoteLength) + "…" : line)
        }
    }

    static let minimumQuiet: TimeInterval = 24 * 3600
    static let maximumQuiet: TimeInterval = 30 * 24 * 3600
    /// Words in a last message that mean "not now".
    static let deferrals = ["later", "tomorrow", "next week", "come back to"]
    static let quoteLength = 40
    static let maximumDeferralLength = 200
}
