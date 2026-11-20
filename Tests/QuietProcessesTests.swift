import Foundation
import Testing
@testable import BroomCore

@Suite("Quiet processes")
struct QuietProcessesTests {
    private let now = TestClock.at(10 * 24 * 3600)

    /// A session last active `ago` seconds before `now`.
    private func session(_ id: String, _ state: LiveState, ago: TimeInterval, cwd: String? = "/code/app", pid: Int32? = nil) -> LiveSession {
        let date = now.addingTimeInterval(-ago)
        return LiveSession(
            id: id, title: id, cwd: cwd, state: state, startedAt: date.addingTimeInterval(-3600),
            lastActivityAt: date, stateChangedAt: date, userTurns: 3, toolCalls: 5, pid: pid
        )
    }

    @Test("Idle means quiet for two hours with a live process, and not working or waiting")
    func idle() {
        let quiet = QuietProcesses(
            sessions: [
                session("quiet-open", .done, ago: 3 * 3600, pid: 10), session("recent-open", .done, ago: 600, pid: 11),
                session("quiet-closed", .done, ago: 3 * 3600), session("waiting", .waiting, ago: 3 * 3600, pid: 12),
                session("running", .running, ago: 3 * 3600, pid: 13),
            ],
            now: now
        )

        #expect(quiet.idle.map(\.id) == ["quiet-open"])
        #expect(!quiet.isEmpty)
    }

    @Test("Processes with no session are listed, the longest running first")
    func unmatched() {
        let quiet = QuietProcesses(
            unmatchedProcesses: [
                ClaudeProcess(pid: 2, cwd: "/code/y", startedAt: now.addingTimeInterval(-60)),
                ClaudeProcess(pid: 1, cwd: "/code/x", startedAt: now.addingTimeInterval(-7200)),
            ],
            now: now
        )

        #expect(quiet.unmatched.map(\.pid) == [1, 2])
        #expect(QuietProcesses().isEmpty)
    }

    @Test("The registry reports processes that no session was given")
    func registryReportsUnmatched() {
        var registry = SessionRegistry(sessions: [session("s", .running, ago: 5, cwd: "/code/app")])
        let mine = ClaudeProcess(pid: 1, cwd: "/code/app", startedAt: now.addingTimeInterval(-7200))
        let stray = ClaudeProcess(pid: 2, cwd: "/code/elsewhere", startedAt: now.addingTimeInterval(-7200))

        registry.tick(at: now, processes: [mine, stray])

        #expect(registry.unmatchedProcesses == [stray])
    }
}
