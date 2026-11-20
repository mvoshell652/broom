/// Where a session comes from. Only `claudeCode` is produced in v0.
public enum SessionSourceKind: String, Codable, Sendable {
    case claudeCode
    case web
    case desktop
}
