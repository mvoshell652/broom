import Foundation
import Testing
@testable import BroomCore

/// Fallback inference without hooks: sessions known only from their transcript.
@Suite("StateMachine: fallback inference without hooks")
struct FallbackInferenceTests {
    /// Parses `fixture`, hands it to the state machine at `seconds`, then ticks at the same moment.
    private func infer(_ fixture: Fixture, at seconds: TimeInterval, processID: Int32? = 4242) throws -> StateMachine.Outcome {
        let digest = try fixture.digest
        let created = StateMachine.apply(.transcriptActivity(digest), to: nil, at: seconds)
        let ticked = StateMachine.apply(.tick(processID: processID), to: created.session, at: seconds)
        return StateMachine.Outcome(session: ticked.session, effects: created.effects + ticked.effects)
    }

    // MARK: Rule 1: pending tool_use for 20 s with a live process → waiting

    @Test("A tool call with no result after 20 s and a live process is inferred waiting")
    func pendingToolIsWaiting() throws {
        // The tool call was written at +4 s.
        let outcome = try infer(.waitingPermission, at: 24)

        let session = try #require(outcome.session)
        #expect(session.state == .waiting)
        #expect(session.isInferred)
        #expect(session.waitingMessage == "May need permission for Bash")
        #expect(outcome.effects.isEmpty)
    }

    @Test("A pending question tool is worded as a question, not a permission prompt", arguments: ["AskUserQuestion", "ExitPlanMode"])
    func questionTools(tool: String) {
        let verdict = FallbackInference.verdict(
            tail: .pendingTool(name: tool), lastActivityAt: TestClock.start, now: TestClock.at(20), processAlive: true
        )

        #expect(verdict == .waiting(message: "Asked you a question"))
    }

    @Test("A pending tool call holds running between 15 s and 20 s, then waits")
    func pendingToolBoundaries() throws {
        #expect(try infer(.waitingPermission, at: 4 + 14).session?.state == .running)
        #expect(try infer(.waitingPermission, at: 4 + 19).session?.state == .running)
        #expect(try infer(.waitingPermission, at: 4 + 20).session?.state == .waiting)
    }

    @Test("A pending tool call with no live process is done, not waiting")
    func pendingToolWithoutProcess() throws {
        #expect(try infer(.waitingPermission, at: 60, processID: nil).session?.state == .done)
    }

    // MARK: Rule 2: assistant text ending in "?" and 30 s of silence with a live process → waiting

    @Test("An assistant question unanswered for 30 s with a live process is inferred waiting")
    func questionIsWaiting() throws {
        // The question was written at +8 s.
        let outcome = try infer(.waitingQuestion, at: 38)

        let session = try #require(outcome.session)
        #expect(session.state == .waiting)
        #expect(session.isInferred)
        #expect(session.waitingMessage?.hasSuffix("staging or production?") == true)
        #expect(outcome.effects.isEmpty)
    }

    @Test("A question holds running until 30 s have passed")
    func questionBoundaries() throws {
        #expect(try infer(.waitingQuestion, at: 8 + 29).session?.state == .running)
        #expect(try infer(.waitingQuestion, at: 8 + 30).session?.state == .waiting)
    }

    @Test("A question with no live process is done")
    func questionWithoutProcess() throws {
        #expect(try infer(.waitingQuestion, at: 120, processID: nil).session?.state == .done)
    }

    // MARK: Rule 3: new lines in the last 15 s → running

    @Test("Lines in the last 15 s mean running, whatever the tail and process", arguments: Fixture.allCases, [Int32?.none, 4242])
    func recentLinesAreRunning(fixture: Fixture, processID: Int32?) throws {
        let lastActivity = try #require(try fixture.digest.lastActivityAt)
        let seconds = lastActivity.timeIntervalSince(TestClock.start) + 14

        let session = try #require(try infer(fixture, at: seconds, processID: processID).session)

        #expect(session.state == .running)
        #expect(session.isInferred)
    }

    // MARK: Rule 4: otherwise → done (or quick)

    @Test("A quiet transcript with nothing pending is done")
    func quietIsDone() throws {
        // Last line at +100 s.
        let session = try #require(try infer(.done, at: 100 + 15).session)

        #expect(session.state == .done)
        #expect(session.isInferred)
        #expect(session.title == "Fix flaky login test")
        #expect(session.repoName == "mobile-app")
        // The turn ended when the transcript went quiet, not when Broom looked.
        #expect(session.stateChangedAt == TestClock.at(100))
    }

    @Test("A session Broom watched finish is stamped when it finished watching, so a popover closed meanwhile still shows it")
    func watchedFinishIsStampedNow() throws {
        // Last line at +100 s. Broom sees it at +101 s as running; the tick at +116 s finds it finished.
        let running = StateMachine.apply(.transcriptActivity(try Fixture.done.digest), to: nil, at: 101).session
        #expect(running?.state == .running)

        let finished = try #require(StateMachine.apply(.tick(processID: nil), to: running, at: 116).session)
        #expect(finished.state == .done)
        #expect(finished.stateChangedAt == TestClock.at(116))

        // The popover was closed at +105 s, after the last line but before the session was seen to finish.
        let sections = LiveSections(sessions: [finished], lastPopoverOpenedAt: TestClock.at(105), now: TestClock.at(120))
        #expect(sections.doneSinceLooked.map(\.id) == [finished.id])
    }

    @Test("A quiet one-question transcript is a quick chat")
    func quietQuickChat() throws {
        let session = try #require(try infer(.quick, at: 60).session)

        #expect(session.state == .quick)
        #expect(session.userTurns == 1)
        #expect(session.toolCalls == 0)
    }

    @Test("A mid-turn transcript that went quiet is done once 15 s pass")
    func runningFixtureGoesDone() throws {
        // Last line (a subagent's) at +40 s.
        #expect(try infer(.running, at: 40 + 14).session?.state == .running)
        #expect(try infer(.running, at: 40 + 15).session?.state == .done)
    }

    // MARK: Inferred states over time

    @Test("An inferred session moves running → waiting as ticks pass, and back to running on new lines")
    func inferredLifecycle() throws {
        let digest = try Fixture.waitingPermission.digest
        var session = StateMachine.apply(.transcriptActivity(digest), to: nil, at: 5).session
        #expect(session?.state == .running)

        session = StateMachine.apply(.tick(processID: 4242), to: session, at: 10).session
        #expect(session?.state == .running)

        let waiting = StateMachine.apply(.tick(processID: 4242), to: session, at: 25)
        #expect(waiting.session?.state == .waiting)
        #expect(waiting.effects.isEmpty)

        var resumed = digest
        resumed.lastActivityAt = TestClock.at(40)
        resumed.tail = .other
        session = StateMachine.apply(.transcriptActivity(resumed), to: waiting.session, at: 41).session
        #expect(session?.state == .running)
        #expect(session?.waitingMessage == nil)
    }

    @Test("Inferred waiting never produces a notification effect", arguments: [Fixture.waitingPermission, .waitingQuestion])
    func inferredWaitingNeverNotifies(fixture: Fixture) throws {
        let digest = try fixture.digest
        var session = StateMachine.apply(.transcriptActivity(digest), to: nil, at: 5).session
        var effects: [SessionEffect] = []

        for seconds in stride(from: 10.0, through: 600, by: 5) {
            let outcome = StateMachine.apply(.tick(processID: 4242), to: session, at: seconds)
            session = outcome.session
            effects += outcome.effects
        }

        #expect(session?.state == .waiting)
        #expect(session?.isInferred == true)
        #expect(effects.isEmpty)
    }

    @Test("A hook event takes a session out of inference for good")
    func hookEndsInference() throws {
        let inferred = try #require(try infer(.waitingPermission, at: 30).session)
        #expect(inferred.isInferred)

        let approved = try #require(StateMachine.apply(.toolActivity(.finished), to: inferred, at: 35).session)
        #expect(approved.state == .running)
        #expect(approved.isInferred == false)
        #expect(approved.hasHookEvents)

        // With hooks present, the stale pending-tool tail no longer drags it back to waiting.
        let later = StateMachine.apply(.tick(processID: 4242), to: approved, at: 120)
        #expect(later.session?.state == .running)
    }

    @Test("An old transcript found at launch is done, then ended once a day has passed with no process")
    func oldTranscript() throws {
        let twoDays = 48 * TestClock.hour
        let digest = try Fixture.done.digest

        let created = try #require(StateMachine.apply(.transcriptActivity(digest), to: nil, at: twoDays).session)
        #expect(created.state == .done)

        let ticked = try #require(StateMachine.apply(.tick(processID: nil), to: created, at: twoDays + 5).session)
        #expect(ticked.state == .ended)

        // Re-reading the same bytes later does not bring it back.
        let reread = StateMachine.apply(.transcriptActivity(digest), to: ticked, at: twoDays + 10)
        #expect(reread.session?.state == .ended)
    }

    @Test("New transcript lines bring back an ended session that has no hooks")
    func endedHooklessSessionResumes() throws {
        let ended = LiveSession.fixture(.ended, hasHookEvents: false, pid: nil)
        let digest = TranscriptDigest(lastActivityAt: TestClock.at(99), counts: ActivityCounts(userTurns: 4, toolCalls: 5))

        let session = try #require(StateMachine.apply(.transcriptActivity(digest), to: ended, at: 100).session)

        #expect(session.state == .running)
        #expect(session.isInferred)
    }

    // MARK: The verdict function

    @Test("Verdict boundaries", arguments: [
        (tail: TranscriptTail.other, age: 14.9, alive: true, expected: FallbackInference.Verdict.running),
        (tail: .other, age: 15, alive: true, expected: .finished),
        (tail: .other, age: 15, alive: false, expected: .finished),
        (tail: .pendingTool(name: "Edit"), age: 19.9, alive: true, expected: .running),
        (tail: .pendingTool(name: "Edit"), age: 20, alive: true, expected: .waiting(message: "May need permission for Edit")),
        (tail: .pendingTool(name: "Edit"), age: 20, alive: false, expected: .finished),
        (tail: .assistantQuestion("Proceed?"), age: 29.9, alive: true, expected: .running),
        (tail: .assistantQuestion("Proceed?"), age: 30, alive: true, expected: .waiting(message: "Proceed?")),
        (tail: .assistantQuestion("Proceed?"), age: 30, alive: false, expected: .finished),
    ])
    func verdict(tail: TranscriptTail, age: TimeInterval, alive: Bool, expected: FallbackInference.Verdict) {
        let verdict = FallbackInference.verdict(
            tail: tail, lastActivityAt: TestClock.start, now: TestClock.at(age), processAlive: alive
        )

        #expect(verdict == expected)
    }
}
