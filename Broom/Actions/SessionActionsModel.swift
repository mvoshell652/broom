import Accessibility
import BroomCore
import SwiftUI

/// Carries out what the user does to sessions: open, snooze, stop.
@MainActor
@Observable
final class SessionActionsModel {
    /// A stop waiting for the user to confirm it. Setting it shows the confirmation in the popover.
    private(set) var pendingStop: StopRequest?
    /// Whether a stop is waiting for an answer. Setting it to `false` cancels the stop, which is what dismissing the dialog does.
    var isConfirmingStop: Bool {
        get { pendingStop != nil }
        set { if !newValue { cancelStop() } }
    }

    /// A short message about the last action, shown briefly.
    private(set) var toast: String?

    private let live: LiveViewModel
    private let settings: AppSettings
    private let opener: OpenSession
    private var toastTask: Task<Void, Never>?
    /// Checks, one per stop, of whether interrupted sessions are still running. Kept so that closing the popover can call them off.
    private var forceStopTasks: [UUID: Task<Void, Never>] = [:]

    static let toastDuration: Duration = .seconds(2.5)

    /// How long after an interrupt a process is checked again.
    static let forceStopDelay: Duration = .seconds(3)

    init(live: LiveViewModel, settings: AppSettings, opener: OpenSession) {
        self.live = live
        self.settings = settings
        self.opener = opener
    }

    // MARK: - Open

    func open(_ session: LiveSession) {
        Task {
            switch await opener.open(session, preferredTerminal: settings.preferredTerminal) {
            case .activated, .launched: break
            case .copied: show("Resume command copied")
            case .unavailable: show("This session cannot be resumed from here")
            }
        }
    }

    /// Opens the session with this id, if it is still known. For notification actions.
    func open(sessionID: String) {
        if let session = live.session(withID: sessionID) { open(session) }
    }

    /// Resumes an indexed chat in the terminal.
    func open(_ chat: IndexedChat) {
        open(Self.session(for: chat))
    }

    /// Copies the command that resumes an indexed chat.
    func copyResumeCommand(_ chat: IndexedChat) {
        copyResumeCommand(Self.session(for: chat))
    }

    /// An indexed chat as a session, which is what opening and resuming work on.
    private static func session(for chat: IndexedChat) -> LiveSession {
        let date = chat.lastActivityAt ?? .distantPast
        return LiveSession(
            id: chat.id, title: chat.title, cwd: chat.cwd, state: .ended, startedAt: chat.startedAt ?? date,
            lastActivityAt: date, stateChangedAt: date, transcriptPath: chat.transcriptPath
        )
    }

    func copyResumeCommand(_ session: LiveSession) {
        show(opener.copyCommand(for: session) == .copied ? "Resume command copied" : "This session cannot be resumed from here")
    }

    func revealTranscript(_ session: LiveSession) {
        if !opener.revealTranscript(of: session) { show("No transcript found for this session") }
    }

    /// Opens the Settings window in front. A menu bar app is not the active app, so the window would otherwise open behind everything else.
    func showSettings(using openSettings: OpenSettingsAction) {
        openSettings()
        NSApplication.shared.activate()
    }

    // MARK: - Snooze

    func snooze(_ session: LiveSession, for duration: SnoozeDuration) {
        Task { await live.snooze(sessionID: session.id, until: duration.end(from: Date())) }
    }

    func snooze(sessionID: String, for duration: SnoozeDuration) {
        Task { await live.snooze(sessionID: sessionID, until: duration.end(from: Date())) }
    }

    // MARK: - Stop

    /// Asks to stop one session. Nothing is signalled until `confirmStop()`.
    func requestStop(_ session: LiveSession) {
        guard session.pid != nil else {
            show("No running process found for this session")
            return
        }
        pendingStop = .interrupt([session])
    }

    /// Asks to stop several sessions, leaving out any without a process.
    func requestStop(_ sessions: [LiveSession]) {
        let stoppable = sessions.filter { $0.pid != nil }
        guard !stoppable.isEmpty else {
            show("No running processes found")
            return
        }
        pendingStop = .interrupt(stoppable)
    }

    /// Asks to stop Claude Code processes that belong to no known session.
    func requestStop(processes: [ClaudeProcess]) {
        guard !processes.isEmpty else { return }
        pendingStop = .processes(processes)
    }

    /// Asks to stop every running or waiting session that has a process.
    func requestStopAll() {
        let sessions = (live.sections.waiting + live.sections.running).filter { $0.pid != nil }
        guard !sessions.isEmpty else {
            show("No running processes found")
            return
        }
        pendingStop = .interrupt(sessions)
    }

    func cancelStop() {
        pendingStop = nil
    }

    /// Drops an unanswered stop request. Called when the popover closes, so an old request is never confirmed later.
    func popoverDidClose() {
        pendingStop = nil
        for task in forceStopTasks.values { task.cancel() }
        forceStopTasks = [:]
    }

    /// The sessions of `request` as they are now, leaving out any whose process has changed or gone since it was made.
    private func current(_ sessions: [LiveSession]) -> [LiveSession] {
        sessions.compactMap { requested in
            guard let now = live.session(withID: requested.id), let pid = now.pid, pid == requested.pid else { return nil }
            return now
        }
    }

    /// Carries out the pending stop.
    func confirmStop() {
        guard let request = pendingStop else { return }
        pendingStop = nil
        switch request {
        case .interrupt(let sessions):
            interrupt(current(sessions))
        case .force(let sessions):
            for session in current(sessions) {
                if let pid = session.pid { _ = StopSession.forceStop(pid) }
            }
        case .processes(let processes):
            // `interrupt` refuses anything that is not a Claude Code process, so a reused pid is left alone.
            let stopped = processes.count { StopSession.interrupt($0.pid) == .signalled }
            if stopped == 0 { show("Those processes are no longer running") }
        }
    }

    private func interrupt(_ sessions: [LiveSession]) {
        var signalled: [LiveSession] = []
        for session in sessions {
            guard let pid = session.pid, StopSession.interrupt(pid) == .signalled else { continue }
            signalled.append(session)
        }
        guard !signalled.isEmpty else {
            show("Those sessions are no longer running")
            return
        }
        let id = UUID()
        forceStopTasks[id] = Task {
            defer { forceStopTasks[id] = nil }
            // Claude Code fires no hook for an interrupt, so the sessions are marked here.
            await live.markInterrupted(sessionIDs: signalled.map(\.id))
            // Cancelled when the popover closes: a force-stop question must not be waiting there on the next open.
            do { try await Task.sleep(for: Self.forceStopDelay) } catch { return }
            let stillRunning = signalled.filter { session in session.pid.map(StopSession.isRunning) ?? false }
            guard !stillRunning.isEmpty else { return }
            switch pendingStop {
            case nil:
                pendingStop = .force(stillRunning)
            case .force(let waiting):
                // A second stop's check landed while the first is still being asked about: ask about them together.
                pendingStop = .force(waiting + stillRunning.filter { session in !waiting.contains { $0.id == session.id } })
            case .interrupt, .processes:
                break
            }
        }
    }

    // MARK: - Toast

    /// Shows `message` briefly.
    private func show(_ message: String) {
        toast = message
        // The toast is visual only, so say it for VoiceOver too.
        AccessibilityNotification.Announcement(message).post()
        toastTask?.cancel()
        toastTask = Task {
            do { try await Task.sleep(for: Self.toastDuration) } catch { return }
            toast = nil
        }
    }
}
