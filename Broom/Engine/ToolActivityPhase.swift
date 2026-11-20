/// Which tool hook reported activity.
public enum ToolActivityPhase: Sendable, Equatable {
    /// `PreToolUse`
    case started
    /// `PostToolUse`
    case finished
    /// `PostToolUseFailure`
    case failed
}
