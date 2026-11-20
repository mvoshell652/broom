import Foundation

/// Every session Broom knows about, kept current by feeding it events and periodic ticks.
public struct SessionRegistry: Sendable {
    /// All sessions by id, including ended ones, so a re-read transcript does not recreate them.
    public private(set) var sessionsByID: [String: LiveSession] = [:]

    /// The processes seen at the last tick, used to give a newly found session its process at once.
    private var processes: [ClaudeProcess] = []
    private var changedIDs: Set<String> = []
    /// The processes from the last tick that no session was given.
    public private(set) var unmatchedProcesses: [ClaudeProcess] = []

    /// Creates a registry holding `sessions`, for example the ones saved by the last launch.
    public init(sessions: [LiveSession] = []) {
        sessionsByID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Sessions that are not ended, most recently active first.
    ///
    /// - Complexity: O(n log n), where n is the number of known sessions.
    public var liveSessions: [LiveSession] {
        sessionsByID.values
            .filter { $0.state != .ended }
            .sorted { ($0.lastActivityAt, $0.id) > ($1.lastActivityAt, $1.id) }
    }

    /// Applies one event and returns what the app should do about it.
    @discardableResult
    public mutating func apply(_ event: SessionEvent) -> [SessionEffect] {
        let isNew = sessionsByID[event.sessionID] == nil
        var effects = reduce(event)
        if isNew, sessionsByID[event.sessionID] != nil, !processes.isEmpty {
            // Without this a new session would look processless, and possibly finished, until the next tick.
            let assignment = ProcessMatcher.assign(processes, to: Array(sessionsByID.values))
            let tick = SessionSignal.tick(processID: assignment[event.sessionID])
            effects += reduce(SessionEvent(sessionID: event.sessionID, date: event.date, signal: tick))
        }
        return effects
    }

    /// Advances every session to `now`, given the Claude Code processes currently running.
    @discardableResult
    public mutating func tick(at now: Date, processes: [ClaudeProcess]) -> [SessionEffect] {
        self.processes = processes
        let assignment = ProcessMatcher.assign(processes, to: Array(sessionsByID.values))
        let matched = Set(assignment.values)
        unmatchedProcesses = processes.filter { !matched.contains($0.pid) }
        var effects: [SessionEffect] = []
        for id in sessionsByID.keys {
            effects += reduce(SessionEvent(sessionID: id, date: now, signal: .tick(processID: assignment[id])))
        }
        return effects
    }

    /// Sets or clears a session's snooze.
    public mutating func snooze(sessionID: String, until date: Date?) {
        // Only a waiting session can be snoozed: a stale notification's Snooze must not hide a later wait.
        guard var session = sessionsByID[sessionID], session.snoozedUntil != date, date == nil || session.state == .waiting else { return }
        session.snoozedUntil = date
        sessionsByID[sessionID] = session
        changedIDs.insert(sessionID)
    }

    /// Every known session, ended ones included, in no particular order.
    public var allSessions: [LiveSession] {
        Array(sessionsByID.values)
    }

    /// Records that Broom interrupted a session's process at the user's request.
    public mutating func markInterrupted(sessionID: String, at date: Date) {
        _ = reduce(SessionEvent(sessionID: sessionID, date: date, signal: .interruptedByUser))
    }

    /// Marks sessions as changed again, for when saving them failed.
    public mutating func markChanged(_ sessions: [LiveSession]) {
        changedIDs.formUnion(sessions.map(\.id))
    }

    /// Returns the sessions that changed since the last call, for saving.
    public mutating func takeChangedSessions() -> [LiveSession] {
        defer { changedIDs.removeAll() }
        return changedIDs.compactMap { sessionsByID[$0] }
    }

    private mutating func reduce(_ event: SessionEvent) -> [SessionEffect] {
        let before = sessionsByID[event.sessionID]
        let outcome = StateMachine.reduce(before, event)
        if let session = outcome.session, session != before {
            sessionsByID[session.id] = session
            changedIDs.insert(session.id)
        }
        return outcome.effects
    }
}
