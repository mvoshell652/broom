import Foundation

/// The sessions sorted into the Live view's sections.
public struct LiveSections: Equatable, Sendable {
    /// Waiting on the user and not snoozed, most recent first.
    public var waiting: [LiveSession]
    /// Running, plus waiting sessions that are snoozed, most recently active first.
    public var running: [LiveSession]
    /// Finished after the popover was last closed, most recent first.
    public var doneSinceLooked: [LiveSession]
    /// Quick chats, most recent first.
    public var quickChats: [LiveSession]
    /// Sessions whose Claude Code process is alive, or that are running or waiting.
    public var openCount: Int

    /// Sorts `sessions` into sections as of `now`. With no `lastPopoverOpenedAt`, every done session counts as new.
    public init(sessions: [LiveSession], lastPopoverOpenedAt: Date?, now: Date) {
        var waiting: [LiveSession] = []
        var running: [LiveSession] = []
        var done: [LiveSession] = []
        var quick: [LiveSession] = []
        var open = 0

        for session in sessions {
            switch session.state {
            case .waiting:
                if session.isSnoozed(at: now) { running.append(session) } else { waiting.append(session) }
            case .running:
                running.append(session)
            case .done:
                if lastPopoverOpenedAt.map({ session.stateChangedAt > $0 }) ?? true { done.append(session) }
            case .quick:
                quick.append(session)
            case .idle, .ended:
                break
            }
            if session.state != .ended, session.pid != nil || session.state == .running || session.state == .waiting {
                open += 1
            }
        }

        self.waiting = waiting.sorted { ($0.stateChangedAt, $0.id) > ($1.stateChangedAt, $1.id) }
        self.running = running.sorted { ($0.lastActivityAt, $0.id) > ($1.lastActivityAt, $1.id) }
        self.doneSinceLooked = done.sorted { ($0.stateChangedAt, $0.id) > ($1.stateChangedAt, $1.id) }
        self.quickChats = quick.sorted { ($0.lastActivityAt, $0.id) > ($1.lastActivityAt, $1.id) }
        self.openCount = open
    }

    /// Every listed session from top to bottom, the order the arrow keys move through.
    ///
    /// - Complexity: O(n), where n is the number of listed sessions.
    public var ordered: [LiveSession] {
        waiting + running + doneSinceLooked + quickChats
    }

    /// The session `offset` rows from the one with `id`, stopping at either end.
    ///
    /// With no selection, or one that is no longer listed, moving down picks the first row and moving up the last.
    public func session(movingFrom id: String?, by offset: Int) -> LiveSession? {
        let rows = ordered
        guard !rows.isEmpty else { return nil }
        guard let id, let index = rows.firstIndex(where: { $0.id == id }) else {
            return offset >= 0 ? rows.first : rows.last
        }
        return rows[min(max(index + offset, 0), rows.count - 1)]
    }

    /// The number on the Live tab: waiting, running and done since you looked.
    public var liveCount: Int {
        waiting.count + running.count + doneSinceLooked.count
    }

    /// The menu bar's number: sessions that are running. A snoozed waiting session is listed under Running but is not counted.
    ///
    /// - Complexity: O(n), where n is the number of running-section sessions.
    public var runningCount: Int {
        running.count { $0.state == .running }
    }

    /// Sessions with an agent at work or blocked.
    public var agentCount: Int {
        waiting.count + running.count
    }

    /// Whether no section has anything to show.
    public var isEmpty: Bool {
        waiting.isEmpty && running.isEmpty && doneSinceLooked.isEmpty && quickChats.isEmpty
    }
}
