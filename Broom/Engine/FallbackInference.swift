import Foundation

/// Infers a session's state from its transcript alone, for sessions with no hooks.
public enum FallbackInference {
    /// What the transcript suggests the session is doing.
    public enum Verdict: Equatable, Sendable {
        case running
        case waiting(message: String)
        /// The turn is over; the caller picks `done` or `quick`.
        case finished
    }

    /// Tools that wait on the user by design, so a pending call is a question, not a permission prompt.
    static let questionTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    static func pendingToolMessage(for toolName: String) -> String {
        questionTools.contains(toolName) ? "Asked you a question" : "May need permission for \(toolName)"
    }

    /// New lines within this window mean the session is running.
    public static let recentActivityWindow: TimeInterval = 15
    /// An unanswered tool call older than this is taken to be a permission prompt.
    public static let pendingToolThreshold: TimeInterval = 20
    /// An assistant question left unanswered this long is taken to be waiting on the user.
    public static let questionThreshold: TimeInterval = 30

    /// Returns what a session with this transcript tail is doing at `now`.
    ///
    /// Between the recent-activity window and a waiting threshold, a live session stays `running`
    /// so it does not flicker through `done` on its way to `waiting`.
    public static func verdict(
        tail: TranscriptTail?,
        lastActivityAt: Date,
        now: Date,
        processAlive: Bool
    ) -> Verdict {
        // An interrupted turn is over at once; new lines replace this tail when the session goes on.
        if tail == .interrupted { return .finished }
        let age = now.timeIntervalSince(lastActivityAt)
        if age < recentActivityWindow { return .running }
        guard processAlive else { return .finished }

        switch tail {
        case .pendingTool(let name):
            return age >= pendingToolThreshold ? .waiting(message: pendingToolMessage(for: name)) : .running
        case .assistantQuestion(let question):
            return age >= questionThreshold ? .waiting(message: question) : .running
        case .interrupted, .other, nil:
            return .finished
        }
    }
}
