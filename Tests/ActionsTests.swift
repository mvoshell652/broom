import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("Session actions")
struct ActionsTests {
    private func session(id: String = "11111111-1111-4111-8111-111111111111", cwd: String? = "/Users/dev/code/acme api") -> LiveSession {
        LiveSession(id: id, cwd: cwd, state: .done, startedAt: TestClock.start, lastActivityAt: TestClock.start, stateChangedAt: TestClock.start)
    }

    // MARK: Resume command

    @Test("The resume command changes to the session's folder, quoted, then resumes by id")
    func resumeCommand() {
        #expect(ResumeCommand.command(for: session()) == "cd -- '/Users/dev/code/acme api' && claude --resume 11111111-1111-4111-8111-111111111111")
        #expect(ResumeCommand.command(for: session(cwd: nil)) == "claude --resume 11111111-1111-4111-8111-111111111111")
        #expect(ResumeCommand.command(for: session(cwd: "/it's/here")) == "cd -- '/it'\\''s/here' && claude --resume 11111111-1111-4111-8111-111111111111")
    }

    /// Folder names a shell would act on if they reached it unquoted.
    private static let hostileFolders = [
        "a$(touch PWNED)b", "a`touch PWNED`b", "a;touch PWNED", "a&&touch PWNED", "a|touch PWNED", "a\ntouch PWNED", "it's", "a\"b", "a b*", "~",
    ]

    /// A folder base with a `claude` stand-in on its own PATH that prints where it ran and what it was given.
    private func runInZsh(_ command: String, in base: URL, standIn: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = base
        process.environment = ["PATH": "\(standIn.path):/usr/bin:/bin", "HOME": base.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func makeStandIn(in base: URL) throws -> URL {
        let folder = base.appending(path: "bin")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appending(path: "claude")
        try Data("#!/bin/sh\nprintf '%s\\n%s\\n' \"$PWD\" \"$*\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return folder
    }

    @Test("A folder name full of shell metacharacters reaches the shell as one literal path", arguments: hostileFolders)
    func hostileFolderSurvivesZsh(name: String) throws {
        let scratch = try TemporaryDirectory()
        let base = scratch.url.resolvingSymlinksInPath()
        let standIn = try makeStandIn(in: base)
        let folder = base.appending(path: "work").appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let command = try #require(ResumeCommand.command(for: session(cwd: folder.path)))

        let output = try runInZsh(command, in: base, standIn: standIn)

        #expect(output == "\(folder.path)\n--resume 11111111-1111-4111-8111-111111111111\n")
        #expect(!FileManager.default.fileExists(atPath: base.appending(path: "PWNED").path))
        #expect(!FileManager.default.fileExists(atPath: base.appending(path: "work/PWNED").path))
    }

    @Test("A folder that starts with a dash is not read as an option")
    func dashFolderSurvivesZsh() throws {
        let scratch = try TemporaryDirectory()
        let base = scratch.url.resolvingSymlinksInPath()
        let standIn = try makeStandIn(in: base)
        try FileManager.default.createDirectory(at: base.appending(path: "-P"), withIntermediateDirectories: true)
        let command = try #require(ResumeCommand.command(for: session(cwd: "-P")))

        let output = try runInZsh(command, in: base, standIn: standIn)

        // The shell starts in the real path of the temp folder, so compare against that.
        let physical = try #require(realpath(base.appending(path: "-P").path, nil))
        defer { free(physical) }
        #expect(output == "\(String(cString: physical))\n--resume 11111111-1111-4111-8111-111111111111\n")
    }

    @Test("An id that is not a UUID never reaches a shell command", arguments: ["", "abc", "x; rm -rf ~", "$(whoami)", "11111111-1111-4111-8111-111111111111; ls"])
    func unsafeIDs(id: String) {
        #expect(ResumeCommand.command(for: session(id: id)) == nil)
        #expect(ResumeCommand.script(for: session(id: id)) == nil)
    }

    @Test("The resume script runs the command in a login shell")
    func resumeScript() {
        let script = ResumeCommand.script(for: session(cwd: "/work/repo"))

        #expect(script == "#!/bin/zsh\nexec /bin/zsh -lic 'cd -- '\\''/work/repo'\\'' && claude --resume 11111111-1111-4111-8111-111111111111'\n")
    }

    // MARK: Snooze

    @Test("Snooze 1h ends an hour later; until tomorrow ends at 9:00 the next morning")
    func snoozeDurations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 22, minute: 30)))
        let earlyMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 1)))
        let nextMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 9)))

        #expect(SnoozeDuration.oneHour.end(from: evening, calendar: calendar) == evening.addingTimeInterval(3600))
        #expect(SnoozeDuration.untilTomorrow.end(from: evening, calendar: calendar) == nextMorning)
        // "Tomorrow" is the next calendar day even at 1 am.
        #expect(SnoozeDuration.untilTomorrow.end(from: earlyMorning, calendar: calendar) == nextMorning)
    }

    // MARK: Terminals

    @Test("Each terminal has a distinct bundle id; only real terminals take a script")
    func terminals() {
        #expect(Set(TerminalApp.allCases.map(\.bundleIdentifier)).count == TerminalApp.allCases.count)
        #expect(TerminalApp.terminal.bundleIdentifier == "com.apple.Terminal")
        #expect(TerminalApp.allCases.filter(\.runsScripts) == [.terminal, .iTerm, .ghostty])
    }

    // MARK: Stop

    @Test("An interrupt ends a Claude Code process with SIGINT", .tags(.integration), .timeLimit(.minutes(1)))
    func interrupt() async throws {
        let standIn = try StandInClaude()
        #expect(await standIn.waitUntilRecognised())
        #expect(StopSession.isRunning(standIn.pid))

        let outcome = StopSession.interrupt(standIn.pid)
        standIn.process.waitUntilExit()

        #expect(outcome == .signalled)
        #expect(standIn.process.terminationReason == .uncaughtSignal)
        #expect(standIn.process.terminationStatus == SIGINT)
        #expect(!StopSession.isRunning(standIn.pid))
        #expect(StopSession.interrupt(standIn.pid) == .notRunning)
    }

    @Test("Force stop ends a Claude Code process with SIGTERM, never SIGKILL", .tags(.integration), .timeLimit(.minutes(1)))
    func forceStop() async throws {
        let standIn = try StandInClaude()
        #expect(await standIn.waitUntilRecognised())

        let outcome = StopSession.forceStop(standIn.pid)
        standIn.process.waitUntilExit()

        #expect(outcome == .signalled)
        #expect(standIn.process.terminationReason == .uncaughtSignal)
        #expect(standIn.process.terminationStatus == SIGTERM)
    }

    @Test("A process that is not Claude Code is never signalled", .tags(.integration))
    func refusesOtherProcesses() throws {
        let other = Process()
        other.executableURL = URL(fileURLWithPath: "/bin/sleep")
        other.arguments = ["30"]
        try other.run()
        defer { other.terminate() }

        #expect(StopSession.interrupt(other.processIdentifier) == .notClaude)
        #expect(StopSession.forceStop(other.processIdentifier) == .notClaude)
        #expect(other.isRunning)
        #expect(!StopSession.isRunning(other.processIdentifier))
        #expect(StopSession.interrupt(1) == .notRunning)
        #expect(StopSession.interrupt(-1) == .notRunning)
        #expect(StopSession.interrupt(0) == .notRunning)
    }
}
