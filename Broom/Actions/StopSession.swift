import BroomShared
import Darwin

/// Signals a session's Claude Code process. `SIGKILL` is never sent.
enum StopSession {
    enum Outcome: Equatable, Sendable {
        case signalled
        /// No process has this id any more.
        case notRunning
        /// The id now belongs to something that is not Claude Code, so it was left alone.
        case notClaude
    }

    /// Sends `SIGINT`, as Ctrl-C in the terminal would.
    static func interrupt(_ pid: Int32) -> Outcome {
        signal(pid, with: SIGINT)
    }

    /// Sends `SIGTERM`. Only for a process that ignored the interrupt, and only when the user asks.
    static func forceStop(_ pid: Int32) -> Outcome {
        signal(pid, with: SIGTERM)
    }

    /// Whether `pid` is still a running Claude Code process.
    static func isRunning(_ pid: Int32) -> Bool {
        pid > 1 && kill(pid, 0) == 0 && ProcessInspector.isClaude(pid)
    }

    private static func signal(_ pid: Int32, with signal: Int32) -> Outcome {
        guard pid > 1, kill(pid, 0) == 0 else { return .notRunning }
        // Process ids are reused: never signal something that is not Claude Code.
        guard ProcessInspector.isClaude(pid) else { return .notClaude }
        return kill(pid, signal) == 0 ? .signalled : .notRunning
    }
}
