import Foundation
import Testing
@testable import BroomCore

/// When a state change posts a notification.
@Suite("NotificationPolicy")
struct NotificationPolicyTests {
    private let waiting = LiveSession.fixture(.waiting, waitingMessage: "Claude needs your permission to use Bash")
    private let effect = SessionEffect.notifyWaiting(sessionID: LiveSession.fixtureID)

    @Test("A waiting session notifies with its title and message")
    func waitingNotification() {
        var policy = NotificationPolicy()

        let content = policy.takeNotification(for: effect, session: waiting, at: TestClock.at(10))

        #expect(content == NotificationContent(
            sessionID: LiveSession.fixtureID, kind: .waiting,
            title: "Fixture session", body: "Claude needs your permission to use Bash"
        ))
    }

    @Test("At most one notification per session in five minutes")
    func rateLimit() {
        var policy = NotificationPolicy()

        #expect(policy.takeNotification(for: effect, session: waiting, at: TestClock.at(0)) != nil)
        #expect(policy.takeNotification(for: effect, session: waiting, at: TestClock.at(299)) == nil)
        #expect(policy.takeNotification(for: effect, session: waiting, at: TestClock.at(300)) != nil)
    }

    @Test("The limit is per session")
    func rateLimitPerSession() {
        var policy = NotificationPolicy()
        let other = LiveSession(
            id: "other", title: "Other", state: .waiting, startedAt: TestClock.start,
            lastActivityAt: TestClock.start, stateChangedAt: TestClock.start
        )

        #expect(policy.takeNotification(for: effect, session: waiting, at: TestClock.at(0)) != nil)
        #expect(policy.takeNotification(for: .notifyWaiting(sessionID: "other"), session: other, at: TestClock.at(1)) != nil)
    }

    @Test("Waiting notifications can be turned off, and a declined one does not use up the limit")
    func waitingOff() {
        var policy = NotificationPolicy(notifiesOnWaiting: false)
        #expect(policy.takeNotification(for: effect, session: waiting, at: TestClock.at(0)) == nil)

        policy.notifiesOnWaiting = true
        #expect(policy.takeNotification(for: effect, session: waiting, at: TestClock.at(1)) != nil)
    }

    @Test("Done notifications are off by default and say Finished when on")
    func doneNotifications() {
        let done = LiveSession.fixture(.done)
        let doneEffect = SessionEffect.notifyDone(sessionID: LiveSession.fixtureID, failed: false)
        var policy = NotificationPolicy()
        #expect(policy.takeNotification(for: doneEffect, session: done, at: TestClock.at(0)) == nil)

        policy.notifiesOnDone = true
        let content = policy.takeNotification(for: doneEffect, session: done, at: TestClock.at(1))

        #expect(content?.kind == .done)
        #expect(content?.body == "Finished")
    }

    @Test("A turn that ended on an API error is not announced as finished")
    func failedTurn() {
        var policy = NotificationPolicy(notifiesOnDone: true)

        let content = policy.takeNotification(for: .notifyDone(sessionID: LiveSession.fixtureID, failed: true), session: .fixture(.done), at: TestClock.at(0))

        #expect(content?.body == "Stopped on an error")
    }

    @Test("Nothing is sent for a snoozed session, a session that has moved on, or one that is gone")
    func suppressed() {
        var policy = NotificationPolicy(notifiesOnDone: true)
        let snoozed = LiveSession.fixture(.waiting, snoozedUntil: TestClock.at(3600))

        #expect(policy.takeNotification(for: effect, session: snoozed, at: TestClock.at(0)) == nil)
        #expect(policy.takeNotification(for: effect, session: .fixture(.running), at: TestClock.at(0)) == nil)
        #expect(policy.takeNotification(for: .notifyDone(sessionID: LiveSession.fixtureID, failed: false), session: .fixture(.running), at: TestClock.at(0)) == nil)
        #expect(policy.takeNotification(for: effect, session: nil, at: TestClock.at(0)) == nil)
    }

    @Test("A long or multi-line message is cut to one line of 180 characters")
    func truncation() {
        var policy = NotificationPolicy()
        let long = LiveSession.fixture(.waiting, waitingMessage: "First line\nsecond line " + String(repeating: "x", count: 400))

        let body = policy.takeNotification(for: effect, session: long, at: TestClock.at(0))?.body

        #expect(body?.count == 180)
        #expect(body?.hasPrefix("First line second line xxx") == true)
        #expect(body?.hasSuffix("…") == true)
    }

    @Test("An untitled session is named by its folder; a missing message gets a default")
    func fallbacks() {
        var policy = NotificationPolicy()
        var untitled = LiveSession.fixture(.waiting)
        untitled.title = ""

        let content = policy.takeNotification(for: effect, session: untitled, at: TestClock.at(0))

        #expect(content?.title == "fixture")
        #expect(content?.body == "Waiting for your input")
    }

    @Test("Inferred waiting produces no effect, so it can never notify")
    func inferredNeverReachesThePolicy() throws {
        var registry = SessionRegistry()
        let digest = try Fixture.waitingPermission.digest
        var effects = registry.apply(SessionEvent(sessionID: "w", date: TestClock.at(5), signal: .transcriptActivity(digest)))
        let process = ClaudeProcess(pid: 9, cwd: "/Users/dev/code/webshop", startedAt: TestClock.start)
        effects += registry.tick(at: TestClock.at(60), processes: [process])

        #expect(registry.sessionsByID["w"]?.state == .waiting)
        #expect(effects.isEmpty)
    }
}
