import Foundation

/// Decides which session each running Claude Code process belongs to.
public enum ProcessMatcher {
    /// How much earlier than its process's start a session's last activity may be, to absorb clock rounding.
    static let startSlack: TimeInterval = 5

    /// Returns the process id for each session that has a live process.
    ///
    /// A session whose hooks reported its process keeps that process for as long as it runs. The rest are
    /// matched by working directory: the session's directory is the process's, or inside it (a session
    /// that moved into a subfolder or worktree keeps its process). Several sessions can share a directory,
    /// so each remaining process, newest first, takes one session that was active during its lifetime and
    /// has no process yet. It prefers a session in exactly its directory, then one that began after the
    /// process did over one it would have had to resume, then the most recently active.
    /// Sessions left over have no live process.
    public static func assign(_ processes: [ClaudeProcess], to sessions: [LiveSession]) -> [String: Int32] {
        var assignment: [String: Int32] = [:]
        var unclaimed = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let live = sessions.filter { $0.state != .ended }

        // Hooks say exactly which process a session runs in. If two sessions name one process (after /clear),
        // the most recently active one has it.
        for session in live.sorted(by: { $0.lastActivityAt > $1.lastActivityAt }) {
            // The id of a process that exited can be reused by another, so the session must also have been
            // active within this process's lifetime.
            if let processID = session.hookProcessID, let process = unclaimed[processID],
               session.lastActivityAt >= process.startedAt.addingTimeInterval(-startSlack) {
                unclaimed[processID] = nil
                assignment[session.id] = processID
            }
        }

        let candidates = live
            .filter { $0.cwd != nil && assignment[$0.id] == nil }
            .map { (session: $0, cwd: normalized($0.cwd ?? "")) }

        for process in unclaimed.values.sorted(by: { ($0.startedAt, $0.pid) > ($1.startedAt, $1.pid) }) {
            let processStart = process.startedAt.addingTimeInterval(-startSlack)
            let match = candidates
                .filter { candidate in
                    assignment[candidate.session.id] == nil
                        && candidate.session.lastActivityAt >= processStart
                        && (candidate.cwd == process.cwd || candidate.cwd.hasPrefix(process.cwd + "/"))
                }
                .max { first, second in
                    let firstRank = rank(first.session, cwd: first.cwd, for: process)
                    let secondRank = rank(second.session, cwd: second.cwd, for: process)
                    if firstRank != secondRank {
                        return firstRank < secondRank
                    }
                    return first.session.lastActivityAt < second.session.lastActivityAt
                }
            if let match {
                assignment[match.session.id] = process.pid
            }
        }
        return assignment
    }

    /// How well a session fits a process, before recency: same directory first, then begun within the process's lifetime.
    private static func rank(_ session: LiveSession, cwd: String, for process: ClaudeProcess) -> Int {
        let sameDirectory = cwd == process.cwd ? 2 : 0
        let begunInProcess = session.startedAt >= process.startedAt.addingTimeInterval(-startSlack) ? 1 : 0
        return sameDirectory + begunInProcess
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
