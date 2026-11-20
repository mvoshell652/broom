import BroomCore
import Foundation
import Observation
import os

/// Keeps the session list current from the session sources and the process monitor, and saves it.
@MainActor
@Observable
final class LiveViewModel {
    /// The Live view's sections.
    private(set) var sections: LiveSections
    /// Sessions that are not ended, most recently active first. For the debug window.
    private(set) var sessions: [LiveSession] = []
    /// Processes left running with nothing happening in them, for the bottom of Live.
    private(set) var quietProcesses = QuietProcesses()
    /// The time the sections were computed for; rows show ages relative to it.
    private(set) var now: Date

    /// Which effects become notifications. The app updates it when the user changes their settings.
    var notificationPolicy = NotificationPolicy()
    /// Told the transcript path a hook reported for a session, so it can be read even outside the watched folder.
    /// Returns what the first read of that transcript found, if anything.
    var registerTranscript: (@Sendable (_ sessionID: String, _ path: String) async -> SessionEvent?)?
    /// Posts a notification. `nil` while notifications are unavailable.
    var postNotification: (@MainActor (NotificationContent) -> Void)?

    private var registry = SessionRegistry()
    private var lastPopoverOpenedAt: Date?
    private var pendingSave: Task<Void, Never>?
    private var lastEventPrune = Date.distantPast
    /// The minute `now` was last assigned in, counted from the reference date.
    private var nowMinute: Int
    /// While the popover is showing, its ages follow every update; closed, nothing reads them.
    private var isPopoverOpen = false
    private let sources: [any SessionSource]
    private let store: SessionStore?
    private let processMonitor: ProcessMonitor
    private let tickInterval: Duration
    private let clock: @Sendable () -> Date
    private let log = Logger(subsystem: "app.broom", category: "live")


    /// How long ended sessions stay in the database before they are deleted.
    static let endedSessionRetention: TimeInterval = 7 * 24 * 60 * 60

    /// How often the hook event log is trimmed while the app runs.
    static let eventPruneInterval: TimeInterval = 60 * 60

    /// How long logged hook events are kept.
    static let hookEventRetention: TimeInterval = 7 * 24 * 60 * 60

    init(
        sources: [any SessionSource],
        store: SessionStore?,
        processMonitor: ProcessMonitor = ProcessMonitor(),
        tickInterval: Duration = .seconds(5),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.store = store
        self.processMonitor = processMonitor
        self.tickInterval = tickInterval
        self.clock = clock
        let launch = clock()
        now = launch
        nowMinute = Int(launch.timeIntervalSinceReferenceDate / 60)
        sections = LiveSections(sessions: [], lastPopoverOpenedAt: nil, now: launch)
    }

    /// Restores saved state, then consumes every source and ticks on an interval until the calling task is cancelled.
    func run() async {
        await restore()
        // Know which processes are alive before the first transcript arrives, so nothing starts out looking dead.
        await tick()
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask {
                    for await event in source.events() {
                        await self.apply(event)
                    }
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    // Leave on cancellation instead of running one more tick.
                    do { try await Task.sleep(for: self.tickInterval) } catch { break }
                    await self.tick()
                }
            }
        }
    }

    /// Records that the user has seen the current list. Call when the popover closes, so rows do not vanish while it is open.
    func popoverDidClose() async {
        isPopoverOpen = false
        let date = clock()
        lastPopoverOpenedAt = date
        refresh()
        do {
            try await store?.setLastPopoverOpenedAt(date)
        } catch {
            log.error("Could not save the popover time: \(error)")
        }
    }

    /// Recomputes ages for a popover that is about to be shown.
    func popoverWillOpen() {
        isPopoverOpen = true
        refresh()
    }

    // MARK: - Updates

    private func restore() async {
        let launch = clock()
        do {
            if let store {
                try await store.deleteSessions(endedBefore: launch.addingTimeInterval(-Self.endedSessionRetention))
                try await store.deleteHookEvents(before: launch.addingTimeInterval(-Self.hookEventRetention))
                registry = SessionRegistry(sessions: try await store.loadSessions())
                lastPopoverOpenedAt = try await store.lastPopoverOpenedAt()
            }
        } catch {
            log.error("Could not load saved sessions: \(error)")
        }
        if lastPopoverOpenedAt == nil {
            // First launch: sessions that finished before Broom existed are not news.
            lastPopoverOpenedAt = launch
            try? await store?.setLastPopoverOpenedAt(launch)
        }
        refresh()
    }

    private func apply(_ event: SessionEvent) async {
        var transcriptEvent: SessionEvent?
        if event.signal.isHookSignal, let path = event.transcriptPath {
            transcriptEvent = await registerTranscript?(event.sessionID, path)
        }
        var effects = registry.apply(event)
        if let transcriptEvent {
            effects += registry.apply(transcriptEvent)
        }
        notify(for: effects)
        await saveChanges()
    }

    private func notify(for effects: [SessionEffect]) {
        for effect in effects {
            let sessionID = switch effect {
            case .notifyWaiting(let id), .notifyDone(let id, _): id
            }
            let now = clock()
            if let content = notificationPolicy.takeNotification(for: effect, session: registry.sessionsByID[sessionID], at: now) {
                postNotification?(content)
            }
        }
    }

    // MARK: - User actions

    /// Replaces the sessions with `sessions`. For tests and previews, in place of running the pipeline.
    func seed(_ sessions: [LiveSession]) {
        registry = SessionRegistry(sessions: sessions)
        refresh()
    }

    /// The live session with this id, if there is one.
    func session(withID id: String) -> LiveSession? {
        sessions.first { $0.id == id }
    }

    /// Hides a waiting session from Waiting, and silences its notification, until `date`.
    func snooze(sessionID: String, until date: Date) async {
        registry.snooze(sessionID: sessionID, until: date)
        await saveChanges()
    }

    /// Records that these sessions' processes were interrupted at the user's request.
    func markInterrupted(sessionIDs: [String]) async {
        let date = clock()
        for id in sessionIDs {
            registry.markInterrupted(sessionID: id, at: date)
        }
        await saveChanges()
    }

    private func tick() async {
        let processes = await processMonitor.snapshot()
        let date = clock()
        notify(for: registry.tick(at: date, processes: processes))
        await saveChanges()

        // The app can stay up for weeks, so the event log is also trimmed while it runs.
        if date.timeIntervalSince(lastEventPrune) >= Self.eventPruneInterval {
            lastEventPrune = date
            do {
                try await store?.deleteHookEvents(before: date.addingTimeInterval(-Self.hookEventRetention))
            } catch {
                log.error("Could not trim the hook event log: \(error)")
            }
        }
    }

    private func saveChanges() async {
        let changed = registry.takeChangedSessions()
        refresh()
        guard let store, !changed.isEmpty else { return }

        // Saves start in the order changes were made but run off the main actor, so each waits for the one before it.
        let previous = pendingSave
        let save = Task {
            await previous?.value
            do {
                try await store.save(changed)
            } catch {
                log.error("Could not save \(changed.count) sessions, will retry: \(error)")
                registry.markChanged(changed)
            }
        }
        pendingSave = save
        await save.value
    }

    private func refresh() {
        let current = clock()
        let live = registry.liveSessions
        let updated = LiveSections(sessions: live, lastPopoverOpenedAt: lastPopoverOpenedAt, now: current)
        // Assign only on change, so views that read these are not invalidated every tick.
        if sessions != live { sessions = live }
        let all = registry.allSessions
        let updatedQuiet = QuietProcesses(sessions: all, unmatchedProcesses: registry.unmatchedProcesses, now: current)
        if quietProcesses != updatedQuiet { quietProcesses = updatedQuiet }
        // Closed, nothing shows ages, so `now` only moves when the sections change or a minute passes. Open, it moves on
        // every update: each row's age turns over at its own second, not on the clock's minute.
        let minute = Int(current.timeIntervalSinceReferenceDate / 60)
        if sections != updated || minute != nowMinute || isPopoverOpen {
            sections = updated
            now = current
            nowMinute = minute
        }
    }
}
