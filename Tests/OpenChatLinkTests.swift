import Foundation
import Testing
@testable import Broom
@testable import BroomShared

@Suite("Open chat link")
struct OpenChatLinkTests {
    /// A `KERN_PROCARGS2` buffer: argument count, executable path, padding, arguments, environment.
    private func processArguments(arguments: [String], environment: [String]) -> [UInt8] {
        var count = Int32(arguments.count)
        var bytes = withUnsafeBytes(of: &count) { Array($0) }
        bytes += Array("/usr/local/bin/claude".utf8) + [0, 0, 0]
        for string in arguments + environment { bytes += Array(string.utf8) + [0] }
        return bytes
    }

    @Test("Reads one variable from the environment, not from the arguments")
    func readsEnvironmentValue() {
        let buffer = processArguments(
            arguments: ["claude", "CLAUDE_CODE_HOST_SESSION_ID=local_from-arguments"],
            environment: ["HOME=/Users/dev", "CLAUDE_CODE_HOST_SESSION_ID=local_abc-123", "TERM=xterm"]
        )
        #expect(ProcessInspector.environmentValue(named: "CLAUDE_CODE_HOST_SESSION_ID", inProcessArguments: buffer) == "local_abc-123")
    }

    @Test("Answers nil for an unset variable or a short buffer")
    func missingValue() {
        let buffer = processArguments(arguments: ["claude"], environment: ["HOME=/Users/dev"])
        #expect(ProcessInspector.environmentValue(named: "CLAUDE_CODE_HOST_SESSION_ID", inProcessArguments: buffer) == nil)
        #expect(ProcessInspector.environmentValue(named: "HOME", inProcessArguments: [1, 0]) == nil)
    }

    @Test("Does not match a variable whose name only starts the same")
    func exactName() {
        let buffer = processArguments(arguments: ["claude"], environment: ["CLAUDE_CODE_HOST_SESSION_ID_OLD=local_x"])
        #expect(ProcessInspector.environmentValue(named: "CLAUDE_CODE_HOST_SESSION_ID", inProcessArguments: buffer) == nil)
    }

    @Test("Links a desktop chat id to the app's continue link")
    @MainActor
    func link() {
        #expect(OpenSession.claudeChatLink(hostSessionID: "local_abc-123")?.absoluteString == "claude://code/continue?session=local_abc-123")
    }

    @Test("Refuses ids the Claude app would refuse", arguments: ["", "abc", "local_", "local_a/b", "local_a&x=1", "session_abc"])
    @MainActor
    func refusesBadIDs(id: String) {
        #expect(OpenSession.claudeChatLink(hostSessionID: id) == nil)
    }
}
