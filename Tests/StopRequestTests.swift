import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("StopRequest")
struct StopRequestTests {
    private func session(_ id: String) -> LiveSession {
        LiveSession(id: id, title: "Session \(id)", state: .running, startedAt: TestClock.start, lastActivityAt: TestClock.start, stateChangedAt: TestClock.start)
    }

    private func process(_ pid: Int32, folder: String) -> ClaudeProcess {
        ClaudeProcess(pid: pid, cwd: "/code/\(folder)", startedAt: TestClock.start)
    }

    @Test("The question and its confirm button say one or several")
    func wording() {
        let one = StopRequest.interrupt([session("a")])
        let several = StopRequest.interrupt([session("a"), session("b")])
        let processes = StopRequest.processes([process(1, folder: "x"), process(2, folder: "y")])

        #expect(one.title == "Stop this session?")
        #expect(one.confirmLabel == "Stop")
        #expect(several.title == "Stop 2 sessions?")
        #expect(several.confirmLabel == "Stop All")
        #expect(processes.title == "Stop 2 processes?")
        #expect(StopRequest.force([session("a")]).cancelLabel == "Leave Running")
    }

    @Test("The message names what will be stopped")
    func names() {
        #expect(StopRequest.interrupt([session("a"), session("b")]).message.hasPrefix("Session a\nSession b\n\n"))
        #expect(StopRequest.processes([process(1, folder: "x"), process(2, folder: "y")]).message.hasPrefix("x\ny\n\n"))
    }

    @Test("A request for processes carries no sessions")
    func processesHaveNoSessions() {
        #expect(StopRequest.processes([process(1, folder: "x")]).sessions.isEmpty)
    }
}
