import Foundation
import Testing
@testable import BroomCore
import BroomShared

@Suite("ProcessMonitor")
struct ProcessMonitorTests {
    @Test("Claude Code is recognised by name or executable path", arguments: [
        (name: "claude", path: "/opt/homebrew/bin/claude", expected: true),
        (name: "2.1.285", path: "/Users/dev/.local/share/claude/versions/2.1.285", expected: true),
        (name: "node", path: "/Users/dev/.local/bin/claude", expected: true),
        (name: "node", path: "/opt/homebrew/bin/node", expected: false),
        (name: "claude-helper", path: "/Applications/Other.app/Contents/MacOS/claude-helper", expected: false),
        (name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", expected: false),
        (name: "", path: "", expected: false),
    ])
    func recognition(name: String, path: String, expected: Bool) {
        #expect(ProcessInspector.isClaude(name: name, executablePath: path) == expected)
    }

    @Test("A process's working directory and start time are read from the system")
    func inspectsOwnProcess() throws {
        let process = try #require(ProcessMonitor.process(getpid()))
        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path

        #expect(process.pid == getpid())
        #expect(process.cwd == expected)
        #expect(process.startedAt <= Date())
        #expect(process.startedAt > Date().addingTimeInterval(-TestClock.hour))
    }

    @Test("A pid that does not exist cannot be inspected")
    func missingProcess() {
        #expect(ProcessMonitor.process(Int32.max - 1) == nil)
    }

    @Test("The snapshot finds a running process named claude, with its working directory", .tags(.integration), .timeLimit(.minutes(1)))
    func snapshotFindsClaudeProcess() async throws {
        let standIn = try StandInClaude()

        // The child only becomes `claude` once it has exec'd, so look until it shows up.
        var match: ClaudeProcess?
        _ = await eventually {
            match = await ProcessMonitor().snapshot().first { $0.pid == standIn.pid }
            return match != nil
        }

        let found = try #require(match)
        #expect(standIn.process.isRunning)
        #expect(found.cwd == standIn.directory.path)
        #expect(abs(found.startedAt.timeIntervalSinceNow) < 30)
    }

    @Test("The snapshot never includes this process")
    func snapshotExcludesSelf() async {
        let processes = await ProcessMonitor().snapshot()

        #expect(!processes.contains { $0.pid == getpid() })
    }
}
