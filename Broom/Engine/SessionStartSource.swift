/// The `source` field of a `SessionStart` hook.
public enum SessionStartSource: String, Codable, Sendable {
    case startup
    case resume
    case clear
    case compact
    case fork
}
