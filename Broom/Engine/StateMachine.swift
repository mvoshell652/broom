import Foundation

/// The session state machine: a pure function from a session and an event to the next session.
public enum StateMachine {
    /// The result of applying one event.
    public struct Outcome: Equatable, Sendable {
        /// The session after the event, or `nil` when the event is for an unknown session and should not create one.
        public var session: LiveSession?
        /// What the app should do about the event, such as posting a notification.
        public var effects: [SessionEffect]
    }

    /// A running or waiting session with no activity for this long and no live process becomes idle.
    public static let idleTimeout: TimeInterval = 10 * 60
    /// Finished sessions end, and quick chats hide, after this long.
    public static let retention: TimeInterval = 24 * 60 * 60

    /// Applies `event` to `current` and returns the next session plus any effects.
    public static func reduce(_ current: LiveSession?, _ event: SessionEvent) -> Outcome {
        guard var session = current ?? makeSession(for: event) else {
            return Outcome(session: nil, effects: [])
        }
        let isNew = current == nil
        let now = event.date
        var effects: [SessionEffect] = []

        if let cwd = event.cwd { session.setWorkingDirectory(cwd) }
        if let path = event.transcriptPath { session.transcriptPath = path }
        if let processID = event.processID { session.hookProcessID = processID }
        if event.signal.isHookSignal {
            session.hasHookEvents = true
            if case .assistantQuestion = session.transcriptTail { session.transcriptTail = .other }
        }

        switch event.signal {
        case .sessionStarted(let source, let title):
            applyCustomTitle(title, to: &session)
            touch(&session, at: now)
            if source != .compact || isNew {
                move(&session, to: .running, at: now, inferred: false)
            }

        case .promptSubmitted(let prompt, let title):
            session.hookCounts.userTurns += 1
            session.refreshCounts()
            applyCustomTitle(title, to: &session)
            applyPromptTitle(prompt, to: &session)
            touch(&session, at: now)
            move(&session, to: .running, at: now, inferred: false)

        case .toolActivity(let phase):
            if phase == .started {
                session.hookCounts.toolCalls += 1
                session.refreshCounts()
            }
            touch(&session, at: now)
            switch session.state {
            case .running, .waiting, .idle:
                move(&session, to: .running, at: now, inferred: false)
            case .done, .quick, .ended:
                // A hook that lost the race with `Stop`. It does not revive the session.
                break
            }

        case .permissionRequested(let toolName):
            guard isInTurn(session) else { break }
            touch(&session, at: now)
            move(&session, to: .waiting, at: now, inferred: false)
            session.waitingMessage = toolName.map { "Permission needed for \($0)" } ?? "Permission needed"

        case .notification(let kind, let message):
            switch kind {
            case .needsUser:
                guard isInTurn(session) else { break }
                move(&session, to: .waiting, at: now, inferred: false)
                if let message, !message.isEmpty {
                    session.waitingMessage = message
                } else if session.waitingMessage == nil {
                    session.waitingMessage = "Waiting for your input"
                }
                requestNotification(for: &session, at: now, into: &effects)
            case .idlePrompt:
                guard session.state == .running else { break }
                move(&session, to: .waiting, at: now, inferred: false)
                session.waitingMessage = message.flatMap { $0.isEmpty ? nil : $0 } ?? "Waiting for your input"
                requestNotification(for: &session, at: now, into: &effects)
            case .informational:
                break
            }

        case .stopped:
            guard isInTurn(session) else { break }
            touch(&session, at: now)
            finish(&session, at: now, inferred: false)
            if session.state == .done { effects.append(.notifyDone(sessionID: session.id, failed: false)) }

        case .stopFailed:
            // A turn that died on an API error is never a quick chat.
            guard isInTurn(session) else { break }
            touch(&session, at: now)
            move(&session, to: .done, at: now, inferred: false)
            effects.append(.notifyDone(sessionID: session.id, failed: true))

        case .interruptedByUser:
            // Claude Code fires no `Stop` hook for an interrupt, so the state is set here.
            guard isInTurn(session) else { break }
            // Without hooks the transcript decides the state; this tail keeps it finished until new lines arrive.
            session.transcriptTail = .interrupted
            finish(&session, at: now, inferred: session.isInferred)

        case .sessionEnded:
            move(&session, to: .ended, at: now, inferred: false)

        case .subagentActivity:
            touch(&session, at: now)

        case .transcriptActivity(let digest):
            let advanced = enrich(&session, with: digest, at: now) || isNew
            if session.hasHookEvents {
                if advanced, session.state == .idle {
                    move(&session, to: .running, at: now, inferred: false)
                } else if digest.tail == .interrupted, session.state == .running || session.state == .waiting,
                          let interruptedAt = digest.interruptedAt, interruptedAt > session.stateChangedAt {
                    // The user pressed Esc in the terminal. No hook reports that; the transcript does.
                    // An interrupt from before the session entered this state belongs to an earlier turn.
                    finish(&session, at: now, inferred: false)
                }
            } else if advanced || session.state != .ended {
                applyInference(to: &session, at: now, isNew: isNew)
            }

        case .subagentTranscriptActivity(let date):
            touch(&session, at: date)
            if !session.hasHookEvents, session.state != .ended {
                applyInference(to: &session, at: now)
            }

        case .tick(let processID):
            session.pid = processID
            if !session.hasHookEvents, session.state != .ended {
                applyInference(to: &session, at: now)
            }
            applyTimeouts(to: &session, at: now)
        }

        return Outcome(session: session, effects: effects)
    }

    // MARK: - Session creation

    /// Returns a new session for an event about an unknown session, or `nil` if the event should not create one.
    private static func makeSession(for event: SessionEvent) -> LiveSession? {
        var startedAt = event.date
        var lastActivityAt = event.date

        switch event.signal {
        case .sessionEnded, .subagentActivity, .subagentTranscriptActivity, .tick, .interruptedByUser,
             .notification(.informational, _), .notification(.idlePrompt, _):
            return nil
        case .transcriptActivity(let digest):
            startedAt = digest.startedAt ?? event.date
            lastActivityAt = digest.lastActivityAt ?? event.date
        default:
            break
        }

        return LiveSession(
            id: event.sessionID,
            state: .running,
            startedAt: startedAt,
            lastActivityAt: lastActivityAt,
            stateChangedAt: event.date
        )
    }

    // MARK: - Transitions

    /// Whether a turn is in progress, so the session can start waiting or finish.
    private static func isInTurn(_ session: LiveSession) -> Bool {
        switch session.state {
        case .running, .waiting, .idle: true
        case .done, .quick, .ended: false
        }
    }

    /// Moves `session` to `state`. `date` becomes `stateChangedAt` only when the state actually changes.
    private static func move(_ session: inout LiveSession, to state: LiveState, at date: Date, inferred: Bool?) {
        if session.state != state {
            session.state = state
            session.stateChangedAt = date
        }
        if let inferred { session.isInferred = inferred }
        if state != .waiting {
            session.waitingMessage = nil
            session.hasNotifiedWaiting = false
            // A snooze covers one wait. The next time the session needs the user it shows again.
            session.snoozedUntil = nil
        }
    }

    /// Ends the current turn: `quick` if the session meets the quick-chat rule, otherwise `done`.
    private static func finish(_ session: inout LiveSession, at date: Date, inferred: Bool) {
        move(&session, to: QuickChatRule.matches(session) ? .quick : .done, at: date, inferred: inferred)
    }

    private static func touch(_ session: inout LiveSession, at date: Date) {
        session.lastActivityAt = max(session.lastActivityAt, date)
    }

    private static func requestNotification(
        for session: inout LiveSession,
        at date: Date,
        into effects: inout [SessionEffect]
    ) {
        guard !session.hasNotifiedWaiting, !session.isSnoozed(at: date) else { return }
        session.hasNotifiedWaiting = true
        effects.append(.notifyWaiting(sessionID: session.id))
    }

    // MARK: - Titles

    private static func applyCustomTitle(_ title: String?, to session: inout LiveSession) {
        guard let title, !title.isEmpty else { return }
        session.title = title
        session.hasCustomTitle = true
    }

    private static func applyPromptTitle(_ prompt: String?, to session: inout LiveSession) {
        guard session.title.isEmpty, let prompt, let title = LiveSession.title(fromPrompt: prompt) else { return }
        session.title = title
    }

    // MARK: - Transcript

    /// Copies what the transcript knows into `session`. Returns whether the transcript holds newer activity.
    private static func enrich(_ session: inout LiveSession, with digest: TranscriptDigest, at now: Date) -> Bool {
        session.transcriptCounts = digest.counts
        session.refreshCounts()
        session.progress = digest.progress
        // The question's text is only needed to infer and word a wait when there are no hooks.
        // With hooks it would be assistant text kept for nothing.
        if session.hasHookEvents, case .assistantQuestion = digest.tail {
            session.transcriptTail = .other
        } else {
            session.transcriptTail = digest.tail
        }
        if session.state == .quick, !QuickChatRule.matches(session) {
            // `Stop` arrived before the transcript showed the session's real size.
            move(&session, to: .done, at: now, inferred: nil)
        }

        if let custom = digest.customTitle {
            applyCustomTitle(custom, to: &session)
        } else if !session.hasCustomTitle, let prompt = digest.firstPrompt {
            applyPromptTitle(prompt, to: &session)
        }
        if session.cwd == nil, let cwd = digest.cwd {
            session.setWorkingDirectory(cwd)
        }
        if let startedAt = digest.startedAt {
            session.startedAt = min(session.startedAt, startedAt)
        }
        guard let lastActivityAt = digest.lastActivityAt, lastActivityAt > session.lastActivityAt else {
            return false
        }
        session.lastActivityAt = lastActivityAt
        return true
    }

    /// Sets the state of a session that has no hooks from its transcript. `isNew` marks a session Broom has only just found.
    private static func applyInference(to session: inout LiveSession, at now: Date, isNew: Bool = false) {
        let verdict = FallbackInference.verdict(
            tail: session.transcriptTail,
            lastActivityAt: session.lastActivityAt,
            now: now,
            processAlive: session.pid != nil
        )
        switch verdict {
        case .running:
            move(&session, to: .running, at: now, inferred: true)
        case .waiting(let message):
            move(&session, to: .waiting, at: now, inferred: true)
            session.waitingMessage = message
        case .finished:
            // A session Broom watched finish changed just now, so it counts as "done since you looked".
            // One found already finished (at launch) ended when its transcript went quiet, which is not news.
            finish(&session, at: isNew ? session.lastActivityAt : now, inferred: true)
        }
    }

    // MARK: - Time

    private static func applyTimeouts(to session: inout LiveSession, at now: Date) {
        let processAlive = session.pid != nil
        switch session.state {
        case .running, .waiting:
            if !processAlive, now.timeIntervalSince(session.lastActivityAt) >= idleTimeout {
                move(&session, to: .idle, at: now, inferred: nil)
            }
        case .done, .idle:
            if !processAlive, now.timeIntervalSince(session.stateChangedAt) >= retention {
                move(&session, to: .ended, at: now, inferred: nil)
            }
        case .quick:
            if now.timeIntervalSince(session.lastActivityAt) >= retention {
                move(&session, to: .ended, at: now, inferred: nil)
            }
        case .ended:
            break
        }
    }
}
