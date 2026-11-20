import Foundation

/// A running Claude Code process.
public struct ClaudeProcess: Identifiable, Equatable, Sendable {
    public var pid: Int32
    /// The process id, which identifies a running process.
    public var id: Int32 { pid }
    /// The process's working directory, symlinks resolved.
    public var cwd: String
    public var startedAt: Date

    public init(pid: Int32, cwd: String, startedAt: Date) {
        self.pid = pid
        self.cwd = cwd
        self.startedAt = startedAt
    }
}
