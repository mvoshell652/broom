/// The state a session is shown in.
public enum LiveState: String, Codable, Sendable, CaseIterable {
    /// Blocked until the user answers a permission prompt or a question.
    case waiting
    /// An agent turn is in progress.
    case running
    /// The last turn finished.
    case done
    /// The last turn finished and the session meets the quick-chat rule.
    case quick
    /// Went silent without finishing and has no live process.
    case idle
    /// Over. Hidden from the Live view.
    case ended
}
