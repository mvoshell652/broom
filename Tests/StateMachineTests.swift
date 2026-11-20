import Foundation
import Testing
@testable import BroomCore

/// One test group per row of the state table (`StateMachine`), in order, then the rules that go with it.
@Suite("StateMachine: state table")
struct StateMachineTests {
    // MARK: Row 1: any | SessionStart or first transcript line → running

    @Test("Row 1: SessionStart moves any state to running", arguments: LiveState.allCases)
    func sessionStart(from state: LiveState) throws {
        let outcome = StateMachine.apply(.sessionStarted(source: .startup, title: nil), to: .fixture(state))

        let session = try #require(outcome.session)
        #expect(session.state == .running)
        #expect(session.isInferred == false)
        #expect(outcome.effects.isEmpty)
    }

    @Test("Row 1: SessionStart creates an unknown session as running")
    func sessionStartCreatesSession() throws {
        let event = SessionEvent(
            sessionID: "new", date: TestClock.at(5), signal: .sessionStarted(source: .startup, title: "Named"),
            cwd: "/Users/dev/code/acme-api", transcriptPath: "/t/new.jsonl"
        )

        let session = try #require(StateMachine.reduce(nil, event).session)

        #expect(session.id == "new")
        #expect(session.state == .running)
        #expect(session.startedAt == TestClock.at(5))
        #expect(session.title == "Named")
        #expect(session.repoName == "acme-api")
        #expect(session.transcriptPath == "/t/new.jsonl")
        #expect(session.hasHookEvents)
    }

    @Test("Row 1: the first transcript line creates a running session")
    func firstTranscriptLine() throws {
        let digest = TranscriptDigest(
            cwd: "/Users/dev/code/acme-api", firstPrompt: "Fix the bug",
            startedAt: TestClock.at(28), lastActivityAt: TestClock.at(28),
            counts: ActivityCounts(userTurns: 1)
        )

        let session = try #require(StateMachine.apply(.transcriptActivity(digest), to: nil, at: 30).session)

        #expect(session.state == .running)
        #expect(session.isInferred)
        #expect(session.title == "Fix the bug")
        #expect(session.startedAt == TestClock.at(28))
        #expect(session.hasHookEvents == false)
    }

    // MARK: Row 2 and row 11: any | UserPromptSubmit → running

    @Test("Rows 2 and 11: UserPromptSubmit moves any state to running", arguments: LiveState.allCases)
    func promptSubmit(from state: LiveState) throws {
        let before = LiveSession.fixture(state, waitingMessage: state == .waiting ? "Allow Bash?" : nil)

        let session = try #require(StateMachine.apply(.promptSubmitted(prompt: "Next", title: nil), to: before).session)

        #expect(session.state == .running)
        #expect(session.userTurns == before.userTurns + 1)
        #expect(session.waitingMessage == nil)
        #expect(session.lastActivityAt == TestClock.at(30))
        #expect(session.stateChangedAt == (state == .running ? TestClock.start : TestClock.at(30)))
    }

    // MARK: Row 3: running | tool hooks or new transcript lines → running (refresh lastActivityAt)

    @Test("Row 3: tool hooks keep a running session running and refresh activity",
          arguments: [ToolActivityPhase.started, .finished, .failed])
    func toolActivityWhileRunning(phase: ToolActivityPhase) throws {
        let before = LiveSession.fixture(.running)

        let session = try #require(StateMachine.apply(.toolActivity(phase), to: before, at: 45).session)

        #expect(session.state == .running)
        #expect(session.lastActivityAt == TestClock.at(45))
        #expect(session.stateChangedAt == TestClock.start)
        #expect(session.toolCalls == before.toolCalls + (phase == .started ? 1 : 0))
    }

    @Test("Row 3: new transcript lines refresh a running session")
    func transcriptLinesWhileRunning() throws {
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(44), counts: ActivityCounts(userTurns: 3, toolCalls: 6))

        let session = try #require(StateMachine.apply(.transcriptActivity(digest), to: .fixture(.running), at: 45).session)

        #expect(session.state == .running)
        #expect(session.lastActivityAt == TestClock.at(44))
        #expect(session.toolCalls == 6)
    }

    // MARK: Row 4: running | PermissionRequest → waiting (names the tool; no notification yet)

    @Test("Row 4: PermissionRequest moves running to waiting without notifying")
    func permissionRequest() throws {
        let outcome = StateMachine.apply(.permissionRequested(toolName: "Bash"), to: .fixture(.running))

        let session = try #require(outcome.session)
        #expect(session.state == .waiting)
        #expect(session.waitingMessage == "Permission needed for Bash")
        #expect(session.stateChangedAt == TestClock.at(30))
        #expect(session.isInferred == false)
        #expect(outcome.effects.isEmpty)
    }

    // MARK: Row 5: running | Notification of a waiting type → waiting (store message; notify)

    @Test("Row 5: a waiting-type Notification moves running to waiting, stores the message and notifies")
    func waitingNotification() throws {
        let outcome = StateMachine.apply(
            .notification(.needsUser, message: "Claude needs your permission to use Bash"), to: .fixture(.running)
        )

        let session = try #require(outcome.session)
        #expect(session.state == .waiting)
        #expect(session.waitingMessage == "Claude needs your permission to use Bash")
        #expect(outcome.effects == [.notifyWaiting(sessionID: LiveSession.fixtureID)])
    }

    @Test("Row 5: idle_prompt on a running session is a waiting signal too")
    func idlePromptWhileRunning() throws {
        let outcome = StateMachine.apply(
            .notification(.idlePrompt, message: "Claude is waiting for your input"), to: .fixture(.running)
        )

        #expect(outcome.session?.state == .waiting)
        #expect(outcome.effects == [.notifyWaiting(sessionID: LiveSession.fixtureID)])
    }

    // MARK: Row 6: waiting | Notification of a waiting type → waiting (notify if not yet notified)

    @Test("Row 6: PermissionRequest then Notification notifies exactly once")
    func notifyOncePerWait() throws {
        let requested = StateMachine.apply(.permissionRequested(toolName: "Bash"), to: .fixture(.running), at: 30)
        let notified = StateMachine.apply(.notification(.needsUser, message: "Allow Bash?"), to: requested.session, at: 36)
        let repeated = StateMachine.apply(.notification(.needsUser, message: "Allow Bash?"), to: notified.session, at: 40)

        #expect(requested.effects.isEmpty)
        #expect(notified.effects == [.notifyWaiting(sessionID: LiveSession.fixtureID)])
        #expect(notified.session?.waitingMessage == "Allow Bash?")
        // Waiting began at the PermissionRequest, not at the later Notification.
        #expect(notified.session?.stateChangedAt == TestClock.at(30))
        #expect(repeated.effects.isEmpty)
        #expect(repeated.session?.state == .waiting)
    }

    @Test("Row 6: a new wait after running again notifies again")
    func notifyAgainForNewWait() throws {
        let first = StateMachine.apply(.notification(.needsUser, message: "Allow Bash?"), to: .fixture(.running), at: 30)
        let approved = StateMachine.apply(.toolActivity(.finished), to: first.session, at: 40)
        let second = StateMachine.apply(.notification(.needsUser, message: "Allow Edit?"), to: approved.session, at: 50)

        #expect(second.effects == [.notifyWaiting(sessionID: LiveSession.fixtureID)])
    }

    @Test("Row 6: a snoozed session moves to waiting without notifying")
    func snoozedSessionDoesNotNotify() throws {
        let snoozed = LiveSession.fixture(.running, snoozedUntil: TestClock.at(TestClock.hour))

        let outcome = StateMachine.apply(.notification(.needsUser, message: "Allow Bash?"), to: snoozed)

        #expect(outcome.session?.state == .waiting)
        #expect(outcome.effects.isEmpty)
    }

    // MARK: Row 7: running | Stop and the quick-chat rule → quick

    @Test("Row 7: Stop on a session that meets the quick-chat rule gives quick")
    func stopQuick() throws {
        let chat = LiveSession.fixture(.running, userTurns: 1, toolCalls: 0)

        let session = try #require(StateMachine.apply(.stopped, to: chat, at: 20).session)

        #expect(session.state == .quick)
        #expect(session.stateChangedAt == TestClock.at(20))
    }

    @Test("Row 7: a one-question session goes SessionStart → prompt → Stop → quick")
    func quickChatEndToEnd() throws {
        var session = StateMachine.apply(.sessionStarted(source: .startup, title: nil), to: nil, at: 0).session
        session = StateMachine.apply(.promptSubmitted(prompt: "What is a struct?", title: nil), to: session, at: 5).session
        session = StateMachine.apply(.stopped, to: session, at: 12).session

        #expect(session?.state == .quick)
        #expect(session?.title == "What is a struct?")
        #expect(session?.userTurns == 1)
    }

    // MARK: Row 8: running | Stop or StopFailure → done

    @Test("Row 8: Stop or StopFailure on an agent session gives done",
          arguments: [SessionSignal.stopped, .stopFailed(error: "rate_limit")])
    func stopDone(signal: SessionSignal) throws {
        let session = try #require(StateMachine.apply(signal, to: .fixture(.running), at: 90).session)

        #expect(session.state == .done)
        #expect(session.stateChangedAt == TestClock.at(90))
        #expect(session.lastActivityAt == TestClock.at(90))
    }

    @Test("Row 8: StopFailure is done even when the session is quick-chat sized", arguments: [LiveState.running, .waiting, .idle])
    func stopFailureIsNeverQuick(state: LiveState) {
        let chat = LiveSession.fixture(state, userTurns: 1, toolCalls: 0)

        let outcome = StateMachine.apply(.stopFailed(error: "rate_limit"), to: chat, at: 20)

        #expect(outcome.session?.state == .done)
        #expect(outcome.session?.stateChangedAt == TestClock.at(20))
    }

    @Test("Row 8: a short chat that used a tool is done, not quick")
    func stopWithToolIsDone() {
        let session = LiveSession.fixture(.running, userTurns: 1, toolCalls: 1)

        #expect(StateMachine.apply(.stopped, to: session).session?.state == .done)
    }

    @Test("Row 8: a tool-free chat that ran 10 minutes is done, not quick")
    func stopAfterTenMinutesIsDone() {
        let session = LiveSession.fixture(.running, userTurns: 1, toolCalls: 0)

        #expect(StateMachine.apply(.stopped, to: session, at: 10 * TestClock.minute).session?.state == .done)
    }

    // MARK: Row 9: waiting | Stop or StopFailure → done or quick

    @Test("Row 9: Stop while waiting finishes the session and clears the message",
          arguments: [(userTurns: 3, toolCalls: 5, expected: LiveState.done), (userTurns: 1, toolCalls: 0, expected: .quick)])
    func stopWhileWaiting(userTurns: Int, toolCalls: Int, expected: LiveState) throws {
        let waiting = LiveSession.fixture(
            .waiting, userTurns: userTurns, toolCalls: toolCalls, waitingMessage: "Allow Bash?", hasNotifiedWaiting: true
        )

        let session = try #require(StateMachine.apply(.stopped, to: waiting).session)

        #expect(session.state == expected)
        #expect(session.waitingMessage == nil)
        #expect(session.hasNotifiedWaiting == false)
    }

    // MARK: Row 10: waiting | UserPromptSubmit or new tool activity → running

    @Test("Row 10: tool activity moves waiting back to running",
          arguments: [ToolActivityPhase.started, .finished, .failed])
    func toolActivityWhileWaiting(phase: ToolActivityPhase) throws {
        let waiting = LiveSession.fixture(.waiting, waitingMessage: "Allow Bash?", hasNotifiedWaiting: true)

        let session = try #require(StateMachine.apply(.toolActivity(phase), to: waiting, at: 33).session)

        #expect(session.state == .running)
        #expect(session.waitingMessage == nil)
        #expect(session.stateChangedAt == TestClock.at(33))
    }

    // MARK: Row 12: done / quick / idle | Notification idle_prompt → unchanged

    @Test("Row 12: idle_prompt is ignored for finished and idle sessions", arguments: [LiveState.done, .quick, .idle, .ended])
    func idlePromptIgnored(state: LiveState) {
        let before = LiveSession.fixture(state)

        let outcome = StateMachine.apply(.notification(.idlePrompt, message: "Claude is waiting for your input"), to: before, at: 60)

        #expect(outcome.session?.state == state)
        #expect(outcome.session?.stateChangedAt == TestClock.start)
        #expect(outcome.session?.waitingMessage == nil)
        #expect(outcome.effects.isEmpty)
    }

    @Test("Row 12: waiting-type notifications do not revive finished sessions", arguments: [LiveState.done, .quick, .ended])
    func waitingNotificationIgnoredWhenFinished(state: LiveState) {
        let outcome = StateMachine.apply(.notification(.needsUser, message: "Allow Bash?"), to: .fixture(state))

        #expect(outcome.session?.state == state)
        #expect(outcome.effects.isEmpty)
    }

    @Test("Informational notifications change nothing", arguments: LiveState.allCases)
    func informationalNotification(state: LiveState) {
        let before = LiveSession.fixture(state)
        var expected = before
        expected.hasHookEvents = true

        let outcome = StateMachine.apply(.notification(.informational, message: "Signed in"), to: before)

        #expect(outcome.session == expected)
        #expect(outcome.effects.isEmpty)
    }

    // MARK: Row 13: running | no activity for 10 min and no live process → idle

    @Test("Row 13: running with no activity for 10 minutes and no process becomes idle")
    func idleAfterTenMinutes() throws {
        let session = try #require(StateMachine.apply(.tick(processID: nil), to: .fixture(.running), at: 10 * TestClock.minute).session)

        #expect(session.state == .idle)
        #expect(session.pid == nil)
        #expect(session.stateChangedAt == TestClock.at(10 * TestClock.minute))
    }

    @Test("Row 13: a live process keeps a silent session running")
    func liveProcessPreventsIdle() {
        let outcome = StateMachine.apply(.tick(processID: 4242), to: .fixture(.running), at: 30 * TestClock.minute)

        #expect(outcome.session?.state == .running)
    }

    @Test("Row 13: under 10 minutes without a process is still running")
    func notIdleBeforeTenMinutes() {
        let outcome = StateMachine.apply(.tick(processID: nil), to: .fixture(.running), at: 10 * TestClock.minute - 1)

        #expect(outcome.session?.state == .running)
    }

    @Test("Row 13: a waiting session whose process died also becomes idle")
    func deadWaitingSessionBecomesIdle() {
        let waiting = LiveSession.fixture(.waiting, waitingMessage: "Allow Bash?")

        let outcome = StateMachine.apply(.tick(processID: nil), to: waiting, at: 10 * TestClock.minute)

        #expect(outcome.session?.state == .idle)
        #expect(outcome.session?.waitingMessage == nil)
    }

    // MARK: Row 14: idle | any tool activity or new transcript lines → running

    @Test("Row 14: tool activity wakes an idle session")
    func toolActivityWhileIdle() {
        #expect(StateMachine.apply(.toolActivity(.started), to: .fixture(.idle)).session?.state == .running)
    }

    @Test("Row 14: new transcript lines wake an idle session")
    func transcriptLinesWhileIdle() {
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(29))

        #expect(StateMachine.apply(.transcriptActivity(digest), to: .fixture(.idle)).session?.state == .running)
    }

    @Test("Row 14: re-reading an unchanged transcript does not wake an idle session")
    func unchangedTranscriptWhileIdle() {
        let digest = TranscriptDigest(lastActivityAt: TestClock.start)

        #expect(StateMachine.apply(.transcriptActivity(digest), to: .fixture(.idle)).session?.state == .idle)
    }

    // MARK: Row 15: any | SessionEnd, or process gone + done/idle for 24 h → ended

    @Test("Row 15: SessionEnd ends any session", arguments: LiveState.allCases)
    func sessionEnd(from state: LiveState) {
        #expect(StateMachine.apply(.sessionEnded, to: .fixture(state)).session?.state == .ended)
    }

    @Test("Row 15: done or idle for 24 hours with no process becomes ended", arguments: [LiveState.done, .idle])
    func endedAfterRetention(state: LiveState) {
        let outcome = StateMachine.apply(.tick(processID: nil), to: .fixture(state), at: 24 * TestClock.hour)

        #expect(outcome.session?.state == .ended)
    }

    @Test("Row 15: a live process keeps a day-old done session", arguments: [LiveState.done, .idle])
    func liveProcessPreventsEnded(state: LiveState) {
        let outcome = StateMachine.apply(.tick(processID: 4242), to: .fixture(state), at: 48 * TestClock.hour)

        #expect(outcome.session?.state == state)
    }

    @Test("Row 15: under 24 hours a done session stays", arguments: [LiveState.done, .idle])
    func notEndedBeforeRetention(state: LiveState) {
        let outcome = StateMachine.apply(.tick(processID: nil), to: .fixture(state), at: 24 * TestClock.hour - 1)

        #expect(outcome.session?.state == state)
    }

    @Test("Quick chats hide 24 hours after their last activity, process or not", arguments: [Int32?.none, 4242])
    func quickChatHides(processID: Int32?) {
        let chat = LiveSession.fixture(.quick, userTurns: 1, toolCalls: 0)

        #expect(StateMachine.apply(.tick(processID: processID), to: chat, at: 24 * TestClock.hour - 1).session?.state == .quick)
        #expect(StateMachine.apply(.tick(processID: processID), to: chat, at: 24 * TestClock.hour).session?.state == .ended)
    }

    // MARK: Row 16: any | any hook event carrying agent_id → unchanged (refresh lastActivityAt only)

    @Test("Row 16: subagent events refresh activity and nothing else", arguments: LiveState.allCases)
    func subagentActivity(state: LiveState) {
        let before = LiveSession.fixture(state, waitingMessage: state == .waiting ? "Allow Bash?" : nil)
        var expected = before
        expected.lastActivityAt = TestClock.at(75)

        let outcome = StateMachine.apply(.subagentActivity, to: before, at: 75)

        #expect(outcome.session == expected)
        #expect(outcome.effects.isEmpty)
    }

    @Test("Any hook event marks the session as hook-driven")
    func hookEventsAreRecorded() {
        let hookless = LiveSession.fixture(.running, hasHookEvents: false)

        #expect(StateMachine.apply(.subagentActivity, to: hookless).session?.hasHookEvents == true)
        #expect(StateMachine.apply(.tick(processID: 4242), to: hookless, at: 1).session?.hasHookEvents == false)
    }

    @Test("Row 16: a subagent's transcript refreshes a hook-driven session without changing its state", arguments: LiveState.allCases)
    func subagentTranscriptOnHookSession(state: LiveState) {
        let before = LiveSession.fixture(state, waitingMessage: state == .waiting ? "Allow Bash?" : nil, transcriptTail: .pendingTool(name: "Bash"))
        var expected = before
        expected.lastActivityAt = TestClock.at(70)

        let outcome = StateMachine.apply(.subagentTranscriptActivity(TestClock.at(70)), to: before, at: 75)

        #expect(outcome.session == expected)
    }

    @Test("Row 16: a subagent's transcript does not bring back an ended session that has no hooks")
    func subagentTranscriptOnEndedSession() {
        let ended = LiveSession.fixture(.ended, hasHookEvents: false)

        let outcome = StateMachine.apply(.subagentTranscriptActivity(TestClock.at(70)), to: ended, at: 75)

        #expect(outcome.session?.state == .ended)
    }

    // MARK: Rules under the table

    @Test("A late tool hook after Stop refreshes activity but leaves done and quick alone",
          arguments: [LiveState.done, .quick, .ended], [ToolActivityPhase.started, .finished, .failed])
    func lateToolHook(state: LiveState, phase: ToolActivityPhase) {
        let outcome = StateMachine.apply(.toolActivity(phase), to: .fixture(state), at: 31)

        #expect(outcome.session?.state == state)
        #expect(outcome.session?.lastActivityAt == TestClock.at(31))
    }

    @Test("PermissionRequest does not revive finished sessions", arguments: [LiveState.done, .quick, .ended])
    func permissionRequestIgnoredWhenFinished(state: LiveState) {
        #expect(StateMachine.apply(.permissionRequested(toolName: "Bash"), to: .fixture(state)).session?.state == state)
    }

    @Test("SessionStart with source compact keeps the current state", arguments: LiveState.allCases)
    func compactKeepsState(state: LiveState) {
        let outcome = StateMachine.apply(.sessionStarted(source: .compact, title: nil), to: .fixture(state))

        #expect(outcome.session?.state == state)
        #expect(outcome.session?.stateChangedAt == TestClock.start)
    }

    @Test("An ended session ignores Stop and returns only through SessionStart or a prompt")
    func endedSession() {
        let ended = LiveSession.fixture(.ended)

        #expect(StateMachine.apply(.stopped, to: ended).session?.state == .ended)
        #expect(StateMachine.apply(.tick(processID: 4242), to: ended).session?.state == .ended)
        #expect(StateMachine.apply(.sessionStarted(source: .resume, title: nil), to: ended).session?.state == .running)
    }

    @Test("Stop is ignored once a session is done or quick", arguments: [LiveState.done, .quick])
    func repeatedStop(state: LiveState) {
        let outcome = StateMachine.apply(.stopped, to: .fixture(state), at: 500)

        #expect(outcome.session?.state == state)
        #expect(outcome.session?.stateChangedAt == TestClock.start)
    }

    @Test("Events that say nothing about a new session do not create one", arguments: [
        SessionSignal.sessionEnded, .subagentActivity, .subagentTranscriptActivity(TestClock.start), .tick(processID: nil),
        .notification(.informational, message: nil), .notification(.idlePrompt, message: nil),
    ])
    func unknownSessionNotCreated(signal: SessionSignal) {
        let outcome = StateMachine.apply(signal, to: nil)

        #expect(outcome.session == nil)
        #expect(outcome.effects.isEmpty)
    }

    @Test("A hook for a session Broom has not seen creates it in the right state")
    func unknownSessionCreated() {
        #expect(StateMachine.apply(.toolActivity(.started), to: nil).session?.state == .running)
        #expect(StateMachine.apply(.permissionRequested(toolName: "Bash"), to: nil).session?.state == .waiting)
        #expect(StateMachine.apply(.notification(.needsUser, message: "Allow?"), to: nil).session?.state == .waiting)
        #expect(StateMachine.apply(.stopped, to: nil).session?.state == .quick)
    }

    @Test("A hook event's process id is remembered for the session")
    func hookProcessID() {
        let event = SessionEvent(sessionID: "s", date: TestClock.start, signal: .toolActivity(.started), processID: 4321)

        #expect(StateMachine.reduce(nil, event).session?.hookProcessID == 4321)
    }

    // MARK: Interrupts (no Stop hook fires for these)

    @Test("An interrupt sent by Broom finishes a session in a turn", arguments: [LiveState.running, .waiting, .idle])
    func interruptedByUser(state: LiveState) throws {
        let before = LiveSession.fixture(state, waitingMessage: state == .waiting ? "Allow Bash?" : nil)

        let outcome = StateMachine.apply(.interruptedByUser, to: before, at: 40)

        let session = try #require(outcome.session)
        #expect(session.state == .done)
        #expect(session.stateChangedAt == TestClock.at(40))
        #expect(session.waitingMessage == nil)
        #expect(outcome.effects.isEmpty)
    }

    @Test("An interrupt changes nothing for a finished or unknown session", arguments: [LiveState.done, .quick, .ended])
    func interruptIgnored(state: LiveState) {
        #expect(StateMachine.apply(.interruptedByUser, to: .fixture(state), at: 40).session?.state == state)
        #expect(StateMachine.apply(.interruptedByUser, to: nil).session == nil)
    }

    @Test("An interrupt is not taken for a hook event")
    func interruptIsNotAHook() {
        let hookless = LiveSession.fixture(.running, hasHookEvents: false)

        #expect(StateMachine.apply(.interruptedByUser, to: hookless).session?.hasHookEvents == false)
    }

    @Test("Esc in the terminal, seen in the transcript, finishes a hook-driven session", arguments: [LiveState.running, .waiting])
    func interruptSeenInTranscript(state: LiveState) throws {
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(29), tail: .interrupted, interruptedAt: TestClock.at(29))

        let session = try #require(StateMachine.apply(.transcriptActivity(digest), to: .fixture(state)).session)

        #expect(session.state == .done)
        #expect(session.isInferred == false)
    }

    @Test("An interrupt from an earlier turn does not finish the turn that followed it")
    func interruptFromEarlierTurn() {
        // The session has been running since +0 s; the interrupt in the transcript is from before that.
        // Newer lines have arrived since (a timestamped metadata line), but not yet the new prompt.
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(5), tail: .interrupted, interruptedAt: TestClock.at(-30))

        #expect(StateMachine.apply(.transcriptActivity(digest), to: .fixture(.running)).session?.state == .running)
    }

    @Test("After Broom interrupts a session that has no hooks, later ticks do not put it back in Running")
    func interruptedHooklessSessionStaysFinished() {
        // Active 2 s ago with a pending tool call and a live process: inference alone would say running, then waiting.
        let running = LiveSession.fixture(.running, lastActivityAt: TestClock.at(98), hasHookEvents: false, transcriptTail: .pendingTool(name: "Bash"))

        var session = StateMachine.apply(.interruptedByUser, to: running, at: 100).session
        #expect(session?.state == .done)

        for seconds in [103.0, 110, 125, 200] {
            session = StateMachine.apply(.tick(processID: 4242), to: session, at: seconds).session
            #expect(session?.state == .done, "at +\(seconds) s")
        }

        // A new prompt in the transcript starts it again.
        let resumed = TranscriptDigest(lastActivityAt: TestClock.at(300), counts: ActivityCounts(userTurns: 4, toolCalls: 5), tail: .other)
        #expect(StateMachine.apply(.transcriptActivity(resumed), to: session, at: 301).session?.state == .running)
    }

    @Test("A snooze covers one wait: it is cleared when the session stops waiting")
    func snoozeClearedAfterWait() {
        let snoozed = LiveSession.fixture(.waiting, waitingMessage: "Allow Bash?", snoozedUntil: TestClock.at(3600))

        let approved = StateMachine.apply(.toolActivity(.finished), to: snoozed, at: 40)
        let waitingAgain = StateMachine.apply(.notification(.needsUser, message: "Allow Edit?"), to: approved.session, at: 60)

        #expect(approved.session?.snoozedUntil == nil)
        #expect(waitingAgain.session?.state == .waiting)
        #expect(waitingAgain.effects == [.notifyWaiting(sessionID: LiveSession.fixtureID)])
    }

    @Test("With hooks, the text of a trailing assistant question is not kept on the session")
    func questionTextNotKeptWithHooks() {
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(29), tail: .assistantQuestion("Shall I continue with the migration?"))

        let hooked = StateMachine.apply(.transcriptActivity(digest), to: .fixture(.running)).session
        let hookless = StateMachine.apply(.transcriptActivity(digest), to: .fixture(.running, hasHookEvents: false)).session
        let converted = StateMachine.apply(.toolActivity(.started), to: hookless, at: 40).session

        #expect(hooked?.transcriptTail == .other)
        // Without hooks the question is what a wait is inferred from, and what its card says.
        #expect(hookless?.transcriptTail == .assistantQuestion("Shall I continue with the migration?"))
        #expect(converted?.transcriptTail == .other)
    }

    // MARK: Done notifications

    @Test("A hook-reported finish asks for a done notification; a quick chat does not")
    func doneEffect() {
        let agent = StateMachine.apply(.stopped, to: .fixture(.running))
        let failed = StateMachine.apply(.stopFailed(error: "rate_limit"), to: .fixture(.running))
        let chat = StateMachine.apply(.stopped, to: .fixture(.running, userTurns: 1, toolCalls: 0), at: 20)
        let repeated = StateMachine.apply(.stopped, to: agent.session)

        #expect(agent.effects == [.notifyDone(sessionID: LiveSession.fixtureID, failed: false)])
        #expect(failed.effects == [.notifyDone(sessionID: LiveSession.fixtureID, failed: true)])
        #expect(chat.effects.isEmpty)
        #expect(repeated.effects.isEmpty)
    }

    // MARK: Hooks win over the transcript

    @Test("Once hooks are seen, transcript lines enrich but do not change state",
          arguments: [LiveState.waiting, .done, .quick, .ended])
    func hooksWinOverTranscript(state: LiveState) throws {
        let before = LiveSession.fixture(state, userTurns: 1, toolCalls: 0, waitingMessage: state == .waiting ? "Allow Bash?" : nil)
        let digest = TranscriptDigest(
            lastActivityAt: TestClock.at(29), counts: ActivityCounts(userTurns: 1, toolCalls: 0),
            progress: StepProgress(completed: 1, total: 4), tail: .pendingTool(name: "Bash")
        )

        let session = try #require(StateMachine.apply(.transcriptActivity(digest), to: before).session)

        #expect(session.state == state)
        #expect(session.isInferred == false)
        #expect(session.progress == StepProgress(completed: 1, total: 4))
        #expect(session.lastActivityAt == TestClock.at(29))
    }

    @Test("A quick session turns done when the transcript shows it used tools")
    func quickReclassified() throws {
        let stopped = StateMachine.apply(.stopped, to: nil, at: 30)
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(29), counts: ActivityCounts(userTurns: 4, toolCalls: 12))

        let session = try #require(StateMachine.apply(.transcriptActivity(digest), to: stopped.session, at: 31).session)

        #expect(stopped.session?.state == .quick)
        #expect(session.state == .done)
        // It became done when Broom learned its size, so it can still show under "Done since you looked".
        #expect(session.stateChangedAt == TestClock.at(31))
    }

    @Test("Counts are the larger of what hooks and the transcript report")
    func countsTakeTheMaximum() throws {
        var session = StateMachine.apply(.promptSubmitted(prompt: "Go", title: nil), to: nil, at: 0).session
        session = StateMachine.apply(.toolActivity(.started), to: session, at: 1).session
        // The transcript lags: it has the prompt but not the tool call yet.
        let lagging = TranscriptDigest(lastActivityAt: TestClock.at(0), counts: ActivityCounts(userTurns: 1, toolCalls: 0))
        session = StateMachine.apply(.transcriptActivity(lagging), to: session, at: 2).session
        #expect(session?.userTurns == 1)
        #expect(session?.toolCalls == 1)

        // Broom missed earlier turns; the transcript knows about them.
        let complete = TranscriptDigest(lastActivityAt: TestClock.at(3), counts: ActivityCounts(userTurns: 6, toolCalls: 9))
        session = StateMachine.apply(.transcriptActivity(complete), to: session, at: 4).session
        #expect(session?.userTurns == 6)
        #expect(session?.toolCalls == 9)
    }

    // MARK: Titles

    @Test("The first prompt titles the session; later prompts do not retitle it")
    func promptTitle() {
        var session = StateMachine.apply(.promptSubmitted(prompt: "Fix the login bug", title: nil), to: nil, at: 0).session
        session = StateMachine.apply(.promptSubmitted(prompt: "Now add tests", title: nil), to: session, at: 60).session

        #expect(session?.title == "Fix the login bug")
    }

    @Test("A session title from hooks or the transcript replaces the prompt title")
    func customTitle() {
        var session = StateMachine.apply(.promptSubmitted(prompt: "Fix the login bug", title: nil), to: nil, at: 0).session
        session = StateMachine.apply(.transcriptActivity(TranscriptDigest(customTitle: "Login fix")), to: session, at: 5).session
        #expect(session?.title == "Login fix")

        session = StateMachine.apply(.promptSubmitted(prompt: "More", title: "Renamed by user"), to: session, at: 9).session
        #expect(session?.title == "Renamed by user")
    }
}
