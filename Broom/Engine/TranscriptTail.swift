/// What the end of a transcript looks like, for inferring state without hooks.
public enum TranscriptTail: Codable, Equatable, Sendable {
    /// The assistant called a tool and no result has been written yet.
    case pendingTool(name: String)
    /// The assistant's last text ends with a question mark.
    case assistantQuestion(String)
    /// The user interrupted the turn (Esc or Ctrl-C). No `Stop` hook fires for this.
    case interrupted
    /// Anything else.
    case other
}
