import Foundation
import Testing
@testable import BroomCore

@Suite("SessionStore")
struct SessionStoreTests {
    private let store: SessionStore

    init() throws {
        store = try SessionStore()
    }

    private func richSession(_ id: String = "a", state: LiveState = .waiting) -> LiveSession {
        var session = LiveSession.fixture(
            state, waitingMessage: "Allow Bash?", hasNotifiedWaiting: true,
            snoozedUntil: TestClock.at(TestClock.hour), transcriptTail: .pendingTool(name: "Bash")
        )
        session = LiveSession(
            id: id, title: session.title, cwd: session.cwd, state: state,
            startedAt: session.startedAt, lastActivityAt: TestClock.at(90), stateChangedAt: TestClock.at(60),
            waitingMessage: session.waitingMessage, progress: StepProgress(completed: 2, total: 5),
            userTurns: 4, toolCalls: 9, pid: 4242, snoozedUntil: session.snoozedUntil, isInferred: true,
            hasHookEvents: true, hasNotifiedWaiting: true, hasCustomTitle: true,
            transcriptPath: "/t/\(id).jsonl", transcriptTail: .assistantQuestion("Proceed?")
        )
        session.transcriptCounts = ActivityCounts(userTurns: 4, toolCalls: 7)
        return session
    }

    @Test("A session comes back as it was saved, without its process id")
    func roundTrip() async throws {
        let session = richSession()
        try await store.save([session])

        let loaded = try await store.loadSessions()

        var expected = session
        expected.pid = nil
        #expect(loaded == [expected])
    }

    @Test("Every state can be stored", arguments: LiveState.allCases)
    func states(state: LiveState) async throws {
        try await store.save([richSession(state: state)])

        #expect(try await store.loadSessions().first?.state == state)
    }

    @Test("Saving a session again updates it instead of adding a row")
    func update() async throws {
        var session = richSession()
        try await store.save([session])
        session.state = .done
        session.waitingMessage = nil
        session.progress = nil
        try await store.save([session])

        let loaded = try await store.loadSessions()

        #expect(loaded.count == 1)
        #expect(loaded.first?.state == .done)
        #expect(loaded.first?.waitingMessage == nil)
        #expect(loaded.first?.progress == nil)
    }

    @Test("Only sessions that ended before the cutoff are deleted")
    func deleteEnded() async throws {
        var oldEnded = richSession("old-ended", state: .ended)
        oldEnded.stateChangedAt = TestClock.at(10)
        var recentEnded = richSession("recent-ended", state: .ended)
        recentEnded.stateChangedAt = TestClock.at(500)
        var oldDone = richSession("old-done", state: .done)
        oldDone.stateChangedAt = TestClock.at(10)
        try await store.save([oldEnded, recentEnded, oldDone])

        let removed = try await store.deleteSessions(endedBefore: TestClock.at(100))

        #expect(removed == 1)
        #expect(Set(try await store.loadSessions().map(\.id)) == ["recent-ended", "old-done"])
    }

    @Test("The popover time is nil until set, then returns what was set last")
    func popoverTime() async throws {
        #expect(try await store.lastPopoverOpenedAt() == nil)

        try await store.setLastPopoverOpenedAt(TestClock.at(10))
        try await store.setLastPopoverOpenedAt(TestClock.at(20))

        #expect(try await store.lastPopoverOpenedAt() == TestClock.at(20))
    }

    @Test("Hook events are logged without the prompt or tool data, and pruned by age")
    func hookEvents() async throws {
        let json = #"{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","prompt":"secret prompt","pid":77}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
        try await store.recordHookEvent(payload, receivedAt: TestClock.at(10))
        try await store.recordHookEvent(payload, receivedAt: TestClock.at(500))
        #expect(try await store.hookEventCount() == 2)

        let removed = try await store.deleteHookEvents(before: TestClock.at(100))

        #expect(removed == 1)
        #expect(try await store.hookEventCount() == 1)
    }

    @Test("A session's hook-reported process survives a save, though its live process id does not")
    func hookProcessID() async throws {
        var session = richSession()
        session.hookProcessID = 4321
        try await store.save([session])

        let loaded = try #require(try await store.loadSessions().first)

        #expect(loaded.hookProcessID == 4321)
        #expect(loaded.pid == nil)
    }

    @Test("Settings are nil until set, keep the last value, and do not collide with the popover time")
    func settings() async throws {
        #expect(try await store.setting("notifiesOnDone") == nil)

        try await store.setSetting("notifiesOnDone", to: "0")
        try await store.setSetting("notifiesOnDone", to: "1")
        try await store.setSetting("lastPopoverOpenedAt", to: "not a date")

        #expect(try await store.setting("notifiesOnDone") == "1")
        #expect(try await store.lastPopoverOpenedAt() == nil)
    }

    @Test("A database on disk keeps its contents between opens and creates its folder")
    func onDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "broom-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/broom.sqlite")

        try await SessionStore(url: url).save([richSession()])
        try await SessionStore(url: url).setLastPopoverOpenedAt(TestClock.at(5))

        let reopened = try SessionStore(url: url)
        #expect(try await reopened.loadSessions().map(\.id) == ["a"])
        #expect(try await reopened.lastPopoverOpenedAt() == TestClock.at(5))
    }
}
