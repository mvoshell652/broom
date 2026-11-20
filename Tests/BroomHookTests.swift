import Foundation
import Testing
@testable import BroomCore

/// Runs the real `broom-hook` binary. It must return in under 300 ms when Broom is not running and never writes to stdout.
@Suite("broom-hook", .tags(.integration), .timeLimit(.minutes(1)))
struct BroomHookTests {
    private let token = "helper-test-token"
    private let payload = Data(#"{"session_id":"s1","hook_event_name":"UserPromptSubmit","cwd":"/work/repo","prompt":"Ship it"}"#.utf8)

    /// A port nothing listens on: bind a free one, note it, and let it go.
    private func unusedPort() async throws -> UInt16 {
        let stream = try #require(await HookTestSupport.start(HookServer(port: 0, token: "x")))
        return stream.port
    }

    @Test("An event piped to the helper reaches the server with a timestamp")
    func delivers() async throws {
        let server = try #require(await HookTestSupport.start(HookServer(port: 0, token: token)))
        let support = try HookTestSupport.supportDirectory(token: token + "\n")
        defer { try? FileManager.default.removeItem(at: support) }
        let before = Date()

        let run = try HookTestSupport.runHelper(input: payload, port: server.port, supportDirectory: support)
        var iterator = server.events.makeAsyncIterator()
        let event = try #require(await iterator.next())

        #expect(run.exitCode == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
        #expect(event.sessionID == "s1")
        #expect(event.signal == .promptSubmitted(prompt: "Ship it", title: nil))
        #expect(event.cwd == "/work/repo")
        // Stamped by the helper, not by the server's later clock.
        #expect(event.date >= before.addingTimeInterval(-1))
        #expect(event.date <= Date())
    }

    @Test("With Broom not running the helper exits 0 within its 300 ms limit and prints nothing")
    func brokerDown() async throws {
        let port = try await unusedPort()
        let support = try HookTestSupport.supportDirectory(token: token)
        defer { try? FileManager.default.removeItem(at: support) }
        // The probe server closes its listener some time after it is released.
        try #require(await eventually { !HookTestSupport.isListening(onPort: port) })

        let run = try HookTestSupport.runHelper(input: payload, port: port, supportDirectory: support)

        #expect(run.exitCode == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
        // Under 300 ms. The measured time includes starting the process, so allow that much again.
        #expect(run.duration < 0.6)
    }

    @Test("A server that never answers cannot hold the helper past its time limit")
    func silentServer() async throws {
        // A listening socket that accepts nothing and replies to nothing.
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0 }
        }
        try #require(bound && listen(descriptor, 1) == 0)
        let support = try HookTestSupport.supportDirectory(token: token)
        defer { try? FileManager.default.removeItem(at: support) }

        let run = try HookTestSupport.runHelper(input: payload, port: UInt16(bigEndian: address.sin_port), supportDirectory: support)

        #expect(run.exitCode == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.duration < 1)
    }

    @Test("With stdin closed the helper still exits 0 and prints nothing")
    func closedStdin() throws {
        let support = try HookTestSupport.supportDirectory(token: token)
        defer { try? FileManager.default.removeItem(at: support) }
        let process = Process()
        process.executableURL = HookTestSupport.helperURL
        process.environment = ["BROOM_HOOK_PORT": "1", "BROOM_SUPPORT_DIR": support.path]
        let stderr = Pipe(), stdout = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        // A write-only descriptor as stdin makes every read fail, as a closed stdin does.
        process.standardInput = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(process.terminationReason == .exit)
        #expect(stdout.fileHandleForReading.readDataToEndOfFile().isEmpty)
        #expect(stderr.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @Test("Bad input or a missing token makes the helper exit 0 silently", arguments: [
        (input: "this is not json", hasToken: true),
        (input: "[1,2,3]", hasToken: true),
        (input: "", hasToken: true),
        (input: #"{"session_id":"s1","hook_event_name":"Stop"}"#, hasToken: false),
    ])
    func badInput(input: String, hasToken: Bool) async throws {
        let server = try #require(await HookTestSupport.start(HookServer(port: 0, token: token)))
        // The server stops listening when its event stream is released, so hold the stream until the helper has run.
        defer { withExtendedLifetime(server.events) {} }
        let support = try HookTestSupport.supportDirectory(token: hasToken ? token : nil)
        defer { try? FileManager.default.removeItem(at: support) }

        let run = try HookTestSupport.runHelper(input: Data(input.utf8), port: server.port, supportDirectory: support)

        #expect(run.exitCode == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
    }
}
