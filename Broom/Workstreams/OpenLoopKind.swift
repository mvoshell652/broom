/// How a chat was left unfinished.
public enum OpenLoopKind: Equatable, Sendable {
    /// Claude's last message asked something and nobody answered.
    case question
    /// The user's last message put the work off. The associated value is what they wrote, shortened.
    case deferred(String)
}
