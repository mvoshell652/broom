import Foundation
import Testing
@testable import BroomCore

@Suite("ProcessMatcher")
struct ProcessMatcherTests {
    private func session(
        _ id: String, cwd: String = "/Users/dev/code/app", state: LiveState = .running,
        started: TimeInterval = 0, lastActivity: TimeInterval
    ) -> LiveSession {
        LiveSession(
            id: id, cwd: cwd, state: state,
            startedAt: TestClock.at(started), lastActivityAt: TestClock.at(lastActivity), stateChangedAt: TestClock.start
        )
    }

    private func process(_ pid: Int32, cwd: String = "/Users/dev/code/app", started: TimeInterval) -> ClaudeProcess {
        ClaudeProcess(pid: pid, cwd: cwd, startedAt: TestClock.at(started))
    }

    @Test("A process is matched to the session in its working directory")
    func matchByDirectory() {
        let sessions = [session("a", lastActivity: 50), session("b", cwd: "/Users/dev/code/other", lastActivity: 60)]

        let assignment = ProcessMatcher.assign([process(10, started: 0)], to: sessions)

        #expect(assignment == ["a": 10])
    }

    @Test("With several sessions in one directory, the process goes to the most recently active")
    func mostRecentWins() {
        let sessions = [session("old", state: .done, lastActivity: 50), session("current", lastActivity: 500)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions) == ["current": 10])
    }

    @Test("Two processes in one directory go to the two most recent sessions")
    func twoProcesses() {
        let sessions = [session("a", lastActivity: 100), session("b", lastActivity: 200), session("c", lastActivity: 300)]

        let assignment = ProcessMatcher.assign([process(10, started: 0), process(11, started: 150)], to: sessions)

        // The newer process (11) picks first and takes the most recent session.
        #expect(assignment == ["c": 11, "b": 10])
    }

    @Test("A process prefers the session that began during its lifetime over a more recently active older one")
    func sessionBornInProcessWins() {
        // Process 10 (from 0) runs "first"; process 11 (from 500) runs "second", which was active less recently.
        let sessions = [session("first", started: 10, lastActivity: 900), session("second", started: 510, lastActivity: 800)]

        let assignment = ProcessMatcher.assign([process(10, started: 0), process(11, started: 500)], to: sessions)

        #expect(assignment == ["first": 10, "second": 11])
    }

    @Test("After /clear, the process moves to the newer session in the same directory")
    func clearedSession() {
        let sessions = [session("before", state: .done, started: 10, lastActivity: 300), session("after", started: 310, lastActivity: 400)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions) == ["after": 10])
    }

    @Test("A session that moved into a subfolder or worktree keeps its process")
    func sessionInSubdirectory() {
        let sessions = [session("a", cwd: "/Users/dev/code/app/.claude/worktrees/fix", lastActivity: 50)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions) == ["a": 10])
    }

    @Test("A session in exactly the process's directory wins over one in a subfolder")
    func exactDirectoryWins() {
        let sessions = [session("nested", cwd: "/Users/dev/code/app/sub", lastActivity: 900), session("exact", lastActivity: 100)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions) == ["exact": 10])
    }

    @Test("A directory that only shares a name prefix does not match")
    func siblingDirectory() {
        let sessions = [session("sibling", cwd: "/Users/dev/code/app-two", lastActivity: 50)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions).isEmpty)
    }

    @Test("A process reported by a session's hooks belongs to that session, whatever the directories say")
    func hookProcessWins() {
        var hooked = session("hooked", cwd: "/Users/dev/code/elsewhere", lastActivity: 10)
        hooked.hookProcessID = 10
        let sessions = [hooked, session("recent", lastActivity: 900)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions) == ["hooked": 10])
    }

    @Test("A hook-reported process that has exited matches nothing, and the session can still match by directory")
    func staleHookProcess() {
        var hooked = session("hooked", lastActivity: 50)
        hooked.hookProcessID = 999

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: [hooked]) == ["hooked": 10])
        #expect(ProcessMatcher.assign([], to: [hooked]).isEmpty)
    }

    @Test("A reused process id is not taken for the old session's process")
    func reusedProcessID() {
        // "old" went quiet at +100 s and remembers pid 10; a new process with that id started at +5000 s.
        var old = session("old", state: .done, lastActivity: 100)
        old.hookProcessID = 10
        let current = session("current", started: 5010, lastActivity: 5100)

        #expect(ProcessMatcher.assign([process(10, started: 5000)], to: [old, current]) == ["current": 10])
    }

    @Test("When two sessions name one process, the most recently active has it")
    func sharedHookProcess() {
        var before = session("before", state: .done, lastActivity: 100)
        before.hookProcessID = 10
        var after = session("after", lastActivity: 400)
        after.hookProcessID = 10

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: [before, after]) == ["after": 10])
    }

    @Test("A session that went quiet before the process started is not matched to it")
    func sessionOlderThanProcess() {
        let sessions = [session("yesterday", state: .done, lastActivity: 100)]

        #expect(ProcessMatcher.assign([process(10, started: 1000)], to: sessions).isEmpty)
        // Activity a few seconds before the recorded start still counts.
        #expect(ProcessMatcher.assign([process(10, started: 103)], to: sessions) == ["yesterday": 10])
    }

    @Test("Ended sessions and sessions with no directory are never matched")
    func unmatchable() {
        var noDirectory = session("no-cwd", lastActivity: 50)
        noDirectory.cwd = nil
        let sessions = [session("ended", state: .ended, lastActivity: 50), noDirectory]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions).isEmpty)
    }

    @Test("A trailing slash on the session's directory still matches")
    func normalizedDirectory() {
        let sessions = [session("a", cwd: "/Users/dev/code/app/", lastActivity: 50)]

        #expect(ProcessMatcher.assign([process(10, started: 0)], to: sessions) == ["a": 10])
    }
}
