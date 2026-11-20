import Foundation

/// Claude Code processes that are still running with nothing happening in them, which Live offers to stop.
public struct QuietProcesses: Equatable, Sendable {
    /// Sessions that are not working or waiting, have been quiet for `idleThreshold`, and still have a live process.
    public var idle: [LiveSession]
    /// Claude Code processes that belong to no known session.
    public var unmatched: [ClaudeProcess]

    /// How long a session must be quiet before its live process counts as left behind.
    public static let idleThreshold: TimeInterval = 2 * 60 * 60

    /// Picks what is left running as of `now`.
    public init(sessions: [LiveSession] = [], unmatchedProcesses: [ClaudeProcess] = [], now: Date = .distantPast) {
        idle = sessions
            .filter { session in
                session.pid != nil && session.state != .running && session.state != .waiting
                    && now.timeIntervalSince(session.lastActivityAt) >= Self.idleThreshold
            }
            .sorted { ($0.lastActivityAt, $0.id) < ($1.lastActivityAt, $1.id) }
        unmatched = unmatchedProcesses.sorted { ($0.startedAt, $0.pid) < ($1.startedAt, $1.pid) }
    }

    public var isEmpty: Bool { idle.isEmpty && unmatched.isEmpty }
}
