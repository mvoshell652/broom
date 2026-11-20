import Foundation
import Testing
@testable import BroomCore

@Suite("HookServer", .tags(.integration), .timeLimit(.minutes(1)))
struct HookServerTests {
    private let token = "test-token-0123456789"
    private let stop = #"{"session_id":"s1","hook_event_name":"Stop","cwd":"/work/repo","transcript_path":"/t/s1.jsonl","pid":4321}"#

    private func started(now: @escaping @Sendable () -> Date = { TestClock.at(50) }) async throws -> (port: UInt16, events: AsyncStream<SessionEvent>) {
        try #require(await HookTestSupport.start(HookServer(port: 0, token: token, now: now)))
    }

    @Test("An authorised event is accepted and reported with its session, directory and process")
    func accepted() async throws {
        let server = try await started()

        let status = await HookTestSupport.send(HookTestSupport.post(stop, token: token), toPort: server.port)
        var iterator = server.events.makeAsyncIterator()
        let event = await iterator.next()

        #expect(status == 204)
        #expect(event == SessionEvent(
            sessionID: "s1", date: TestClock.at(50), signal: .stopped,
            cwd: "/work/repo", transcriptPath: "/t/s1.jsonl", processID: 4321
        ))
    }

    @Test("Requests without the right token are refused and report nothing", arguments: [String?.none, "wrong-token", ""])
    func unauthorised(candidate: String?) async throws {
        let server = try await started()

        let refused = await HookTestSupport.send(HookTestSupport.post(stop, token: candidate), toPort: server.port)
        // A following authorised event is the first thing the stream reports.
        let prompt = #"{"session_id":"s2","hook_event_name":"UserPromptSubmit","prompt":"Go"}"#
        _ = await HookTestSupport.send(HookTestSupport.post(prompt, token: token), toPort: server.port)
        var iterator = server.events.makeAsyncIterator()

        #expect(refused == 401)
        #expect(await iterator.next()?.sessionID == "s2")
    }

    @Test("Authorization headers that are not exactly the bearer token are refused", arguments: [
        ["Authorization: bearer TOKEN"],
        ["Authorization: BEARER TOKEN"],
        ["Authorization: Bearer  TOKEN"],
        ["Authorization: TOKEN"],
        ["Authorization: Basic TOKEN"],
        ["Authorization: Bearer TOKEN", "Authorization: Bearer wrong-token"],
    ])
    func unusualAuthorization(lines: [String]) async throws {
        let server = try await started()
        let headerLines = lines.map { $0.replacingOccurrences(of: "TOKEN", with: token) }

        let refused = await HookTestSupport.send(HookTestSupport.post(stop, headerLines: headerLines), toPort: server.port)
        let prompt = #"{"session_id":"s2","hook_event_name":"UserPromptSubmit","prompt":"Go"}"#
        _ = await HookTestSupport.send(HookTestSupport.post(prompt, token: token), toPort: server.port)
        var iterator = server.events.makeAsyncIterator()

        #expect(refused == 401)
        #expect(await iterator.next()?.sessionID == "s2")
    }

    @Test("Wrong paths, methods and bodies get the matching status", arguments: [
        (path: "/v1/other", method: "POST", body: #"{"session_id":"s1","hook_event_name":"Stop"}"#, status: 404),
        (path: "/v1/events", method: "GET", body: "", status: 405),
        (path: "/v1/events", method: "POST", body: "not json", status: 400),
        (path: "/v1/events", method: "POST", body: #"{"hook_event_name":"Stop"}"#, status: 400),
    ])
    func rejected(path: String, method: String, body: String, status: Int) async throws {
        let server = try await started()
        // The server stops listening when its event stream is released, so hold the stream for the whole test.
        defer { withExtendedLifetime(server.events) {} }

        let request = HookTestSupport.post(body, token: token, path: path, method: method)

        #expect(await HookTestSupport.send(request, toPort: server.port) == status)
    }

    @Test("An unauthorised client is refused as soon as its headers arrive, without sending its body")
    func refusedBeforeBody() async throws {
        let server = try await started()
        // The server stops listening when its event stream is released, so hold the stream for the whole test.
        defer { withExtendedLifetime(server.events) {} }
        // Declares a large body and never sends it; a server that waited would not answer.
        let request = Data("POST /v1/events HTTP/1.1\r\nAuthorization: Bearer nope\r\nContent-Length: 8000000\r\n\r\n".utf8)

        #expect(await HookTestSupport.send(request, toPort: server.port) == 401)
    }

    @Test("An event Broom does not track is accepted but reports nothing")
    func untrackedEvent() async throws {
        let server = try await started()

        let untracked = HookTestSupport.post(#"{"session_id":"s1","hook_event_name":"PreCompact"}"#, token: token)
        #expect(await HookTestSupport.send(untracked, toPort: server.port) == 204)
        _ = await HookTestSupport.send(HookTestSupport.post(stop, token: token), toPort: server.port)
        var iterator = server.events.makeAsyncIterator()

        #expect(await iterator.next()?.signal == .stopped)
    }

    @Test("The helper's own timestamp is used when it is close to the server's clock, and ignored when it is not")
    func helperTimestamp() async throws {
        let server = try await started(now: { TestClock.at(50) })
        func event(receivedAt: String) -> Data {
            HookTestSupport.post(#"{"session_id":"s1","hook_event_name":"Stop","received_at":"\#(receivedAt)"}"#, token: token)
        }

        _ = await HookTestSupport.send(event(receivedAt: "2026-11-14T10:00:48.500Z"), toPort: server.port)
        _ = await HookTestSupport.send(event(receivedAt: "2026-11-14T09:00:00.000Z"), toPort: server.port)
        var iterator = server.events.makeAsyncIterator()

        #expect(await iterator.next()?.date == TestClock.at(48.5))
        #expect(await iterator.next()?.date == TestClock.at(50))
    }

    @Test("Accepted payloads are handed to the recorder")
    func recorder() async throws {
        let (recorded, continuation) = AsyncStream<String>.makeStream()
        let server = HookServer(port: 0, token: token, record: { payload, _ in continuation.yield(payload.eventName) })
        let running = try #require(await HookTestSupport.start(server))
        defer { withExtendedLifetime(running.events) {} }

        _ = await HookTestSupport.send(HookTestSupport.post(stop, token: token), toPort: running.port)
        var iterator = recorded.makeAsyncIterator()

        #expect(await iterator.next() == "Stop")
    }

    @Test("A second server on a port already in use ends its stream instead of hanging")
    func portInUse() async throws {
        let first = try await started()

        let second = HookServer(port: first.port, token: token).events()
        var iterator = second.makeAsyncIterator()

        #expect(await iterator.next() == nil)
    }
}
