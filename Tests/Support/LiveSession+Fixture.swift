import Foundation
@testable import BroomCore

extension LiveSession {
    static let fixtureID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    /// A session that started at `TestClock.start` and has been in `state` since then.
    ///
    /// The defaults describe a hook-driven agent session that is too big to be a quick chat.
    static func fixture(
        _ state: LiveState,
        userTurns: Int = 3,
        toolCalls: Int = 5,
        lastActivityAt: Date = TestClock.start,
        hasHookEvents: Bool = true,
        pid: Int32? = 4242,
        waitingMessage: String? = nil,
        hasNotifiedWaiting: Bool = false,
        snoozedUntil: Date? = nil,
        transcriptTail: TranscriptTail? = nil
    ) -> LiveSession {
        LiveSession(
            id: fixtureID,
            title: "Fixture session",
            cwd: "/Users/dev/code/fixture",
            state: state,
            startedAt: TestClock.start,
            lastActivityAt: lastActivityAt,
            stateChangedAt: TestClock.start,
            waitingMessage: waitingMessage,
            userTurns: userTurns,
            toolCalls: toolCalls,
            pid: pid,
            snoozedUntil: snoozedUntil,
            hasHookEvents: hasHookEvents,
            hasNotifiedWaiting: hasNotifiedWaiting,
            transcriptTail: transcriptTail
        )
    }
}

extension StateMachine {
    /// Applies `signal` to `session` at `seconds` after `TestClock.start`.
    static func apply(
        _ signal: SessionSignal,
        to session: LiveSession?,
        at seconds: TimeInterval = 30
    ) -> Outcome {
        reduce(session, SessionEvent(sessionID: LiveSession.fixtureID, date: TestClock.at(seconds), signal: signal))
    }
}
