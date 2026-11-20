import Foundation
import Testing
@testable import BroomCore

@Suite("SessionRegistry")
struct SessionRegistryTests {
    private func transcript(_ fixture: Fixture, id: String, at seconds: TimeInterval) throws -> SessionEvent {
        SessionEvent(sessionID: id, date: TestClock.at(seconds), signal: .transcriptActivity(try fixture.digest))
    }

    @Test("Events create and update sessions; ticks move them through time")
    func transcriptOnlyLifecycle() throws {
        var registry = SessionRegistry()
        // The fixture's tool call was written at +4 s and never got a result.
        registry.apply(try transcript(.waitingPermission, id: "w", at: 5))
        #expect(registry.sessionsByID["w"]?.state == .running)

        let process = ClaudeProcess(pid: 77, cwd: "/Users/dev/code/webshop", startedAt: TestClock.start)
        let effects = registry.tick(at: TestClock.at(30), processes: [process])

        let session = try #require(registry.sessionsByID["w"])
        #expect(session.state == .waiting)
        #expect(session.pid == 77)
        #expect(session.isInferred)
        #expect(effects.isEmpty)
    }

    @Test("A session whose process is gone loses its pid and finishes")
    func processGone() throws {
        var registry = SessionRegistry()
        registry.apply(try transcript(.waitingPermission, id: "w", at: 5))
        let process = ClaudeProcess(pid: 77, cwd: "/Users/dev/code/webshop", startedAt: TestClock.start)
        registry.tick(at: TestClock.at(30), processes: [process])

        registry.tick(at: TestClock.at(35), processes: [])

        #expect(registry.sessionsByID["w"]?.pid == nil)
        #expect(registry.sessionsByID["w"]?.state == .done)
    }

    @Test("Live sessions are listed most recent first and leave the list when they end")
    func liveSessions() throws {
        var registry = SessionRegistry()
        registry.apply(try transcript(.quick, id: "quick", at: 60))
        registry.apply(try transcript(.done, id: "done", at: 200))
        #expect(registry.liveSessions.map(\.id) == ["done", "quick"])

        registry.tick(at: TestClock.at(25 * TestClock.hour), processes: [])

        #expect(registry.liveSessions.isEmpty)
        #expect(registry.sessionsByID.count == 2)
    }

    @Test("Events for unknown sessions that should not create one are dropped")
    func unknownSession() {
        var registry = SessionRegistry()

        registry.apply(SessionEvent(sessionID: "ghost", date: TestClock.start, signal: .subagentTranscriptActivity(TestClock.start)))
        registry.apply(SessionEvent(sessionID: "ghost", date: TestClock.start, signal: .sessionEnded))

        #expect(registry.sessionsByID.isEmpty)
    }

    @Test("Hook effects are passed through")
    func effects() {
        var registry = SessionRegistry()
        registry.apply(SessionEvent(sessionID: "h", date: TestClock.start, signal: .promptSubmitted(prompt: "Go", title: nil)))

        let effects = registry.apply(SessionEvent(
            sessionID: "h", date: TestClock.at(10), signal: .notification(.needsUser, message: "Allow Bash?")
        ))

        #expect(effects == [.notifyWaiting(sessionID: "h")])
    }

    @Test("A session found while its process is known gets that process at once")
    func newSessionGetsKnownProcess() throws {
        var registry = SessionRegistry()
        let process = ClaudeProcess(pid: 77, cwd: "/Users/dev/code/webshop", startedAt: TestClock.start)
        registry.tick(at: TestClock.at(1), processes: [process])

        // Found 26 s after its unanswered tool call: without a process it would be created as done.
        registry.apply(try transcript(.waitingPermission, id: "w", at: 30))

        #expect(registry.sessionsByID["w"]?.pid == 77)
        #expect(registry.sessionsByID["w"]?.state == .waiting)
    }

    @Test("Restored sessions are kept, and only changed sessions are reported for saving")
    func changeTracking() throws {
        var registry = SessionRegistry(sessions: [.fixture(.done, pid: nil)])
        #expect(registry.takeChangedSessions().isEmpty)

        registry.tick(at: TestClock.at(5), processes: [])
        #expect(registry.takeChangedSessions().isEmpty)

        registry.apply(try transcript(.quick, id: "q", at: 60))
        #expect(registry.takeChangedSessions().map(\.id) == ["q"])
        #expect(registry.takeChangedSessions().isEmpty)
        #expect(registry.sessionsByID.count == 2)
    }

    @Test("Snoozing a session is reported as a change; an unknown id is ignored")
    func snooze() {
        var registry = SessionRegistry(sessions: [.fixture(.waiting)])

        registry.snooze(sessionID: LiveSession.fixtureID, until: TestClock.at(3600))
        registry.snooze(sessionID: "ghost", until: TestClock.at(3600))

        #expect(registry.sessionsByID[LiveSession.fixtureID]?.snoozedUntil == TestClock.at(3600))
        #expect(registry.takeChangedSessions().map(\.id) == [LiveSession.fixtureID])
    }

    @Test("A session that is not waiting cannot be snoozed, so a stale notification's Snooze hides nothing later")
    func snoozeNeedsWaiting() {
        var registry = SessionRegistry(sessions: [.fixture(.running)])

        registry.snooze(sessionID: LiveSession.fixtureID, until: TestClock.at(3600))

        #expect(registry.sessionsByID[LiveSession.fixtureID]?.snoozedUntil == nil)
        #expect(registry.takeChangedSessions().isEmpty)
    }

    @Test("Subagent transcript activity keeps a transcript-only session running")
    func subagentTranscriptActivity() throws {
        var registry = SessionRegistry()
        registry.apply(try transcript(.running, id: "r", at: 41))
        registry.tick(at: TestClock.at(70), processes: [])
        #expect(registry.sessionsByID["r"]?.state == .done)

        registry.apply(SessionEvent(sessionID: "r", date: TestClock.at(91), signal: .subagentTranscriptActivity(TestClock.at(90))))

        #expect(registry.sessionsByID["r"]?.state == .running)
        #expect(registry.sessionsByID["r"]?.lastActivityAt == TestClock.at(90))
    }
}
