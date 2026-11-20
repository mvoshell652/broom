import Foundation
import Testing
@testable import Broom
@testable import BroomCore

/// Stop all lists sessions, asks for confirmation, sends SIGINT, and the sessions leave Running.
/// The only process signalled here is a stand-in started by the test.
@Suite("SessionActionsModel", .tags(.integration), .timeLimit(.minutes(1)))
@MainActor
struct SessionActionsModelTests {
    private let live = LiveViewModel(sources: [], store: nil)
    private let actions: SessionActionsModel

    init() {
        actions = SessionActionsModel(
            live: live,
            settings: AppSettings(store: nil),
            opener: OpenSession(scriptDirectory: FileManager.default.temporaryDirectory.appending(path: "broom-resume-\(UUID().uuidString)"))
        )
    }

    private func running(_ id: String, pid: Int32?) -> LiveSession {
        LiveSession(
            id: id, title: "Session \(id)", cwd: "/work/\(id)", state: .running,
            startedAt: Date().addingTimeInterval(-600), lastActivityAt: Date(), stateChangedAt: Date().addingTimeInterval(-600),
            userTurns: 3, toolCalls: 9, pid: pid, hasHookEvents: true
        )
    }

    @Test("Asking to stop signals nothing; cancelling leaves the process running")
    func requestThenCancel() async throws {
        let standIn = try StandInClaude()
        #expect(await standIn.waitUntilRecognised())
        live.seed([running("a", pid: standIn.pid)])

        actions.requestStopAll()
        #expect(actions.pendingStop?.sessions.map(\.id) == ["a"])
        #expect(standIn.process.isRunning)

        // Cancelling is synchronous and signals nothing, so there is nothing to wait for.
        actions.cancelStop()

        #expect(actions.pendingStop == nil)
        #expect(standIn.process.isRunning)
        #expect(live.sections.running.map(\.id) == ["a"])
    }

    @Test("Confirming sends SIGINT and the session leaves Running")
    func confirmStops() async throws {
        let standIn = try StandInClaude()
        #expect(await standIn.waitUntilRecognised())
        live.seed([running("a", pid: standIn.pid), running("no-process", pid: nil)])

        actions.requestStopAll()
        // Only the session with a process is listed, because only it can be signalled.
        #expect(actions.pendingStop?.sessions.map(\.id) == ["a"])
        actions.confirmStop()
        standIn.process.waitUntilExit()
        #expect(await eventually { !live.sections.running.contains { $0.id == "a" } })

        #expect(standIn.process.terminationReason == .uncaughtSignal)
        #expect(standIn.process.terminationStatus == SIGINT)
        #expect(live.sections.running.map(\.id) == ["no-process"])
        #expect(live.session(withID: "a")?.state == .done)
    }

    @Test("A request is dropped when the session's process has changed since it was made")
    func staleRequest() async throws {
        let standIn = try StandInClaude()
        #expect(await standIn.waitUntilRecognised())
        live.seed([running("a", pid: standIn.pid)])
        actions.requestStop(running("a", pid: standIn.pid))

        // The session now reports a different process.
        live.seed([running("a", pid: standIn.pid + 1)])
        actions.confirmStop()

        // Nothing was signalled: the model says so at once, where a signalled session would be marked done later.
        #expect(actions.toast == "Those sessions are no longer running")
        #expect(standIn.process.isRunning)
    }

    @Test("Closing the popover drops an unanswered request")
    func popoverClose() {
        live.seed([running("a", pid: 4_000_000)])
        actions.requestStopAll()
        #expect(actions.pendingStop != nil)

        actions.popoverDidClose()

        #expect(actions.pendingStop == nil)
    }

    @Test("With no process to signal, nothing is asked and the reason is shown")
    func nothingToStop() {
        live.seed([running("a", pid: nil)])

        actions.requestStopAll()
        #expect(actions.pendingStop == nil)
        #expect(actions.toast == "No running processes found")

        actions.requestStop(running("a", pid: nil))
        #expect(actions.pendingStop == nil)
        #expect(actions.toast == "No running process found for this session")
    }

    @Test("Snoozing a waiting session moves it out of Waiting")
    func snooze() async throws {
        var waiting = running("w", pid: nil)
        waiting.state = .waiting
        waiting.waitingMessage = "Allow Bash?"
        live.seed([waiting])
        #expect(live.sections.waiting.map(\.id) == ["w"])

        actions.snooze(waiting, for: .oneHour)
        #expect(await eventually { live.sections.waiting.isEmpty })

        #expect(live.sections.waiting.isEmpty)
        #expect(live.sections.running.map(\.id) == ["w"])
        #expect(live.sections.runningCount == 0)
    }
}
