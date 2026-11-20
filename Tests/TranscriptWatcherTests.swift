import Foundation
import Testing
@testable import BroomCore

@Suite("TranscriptWatcher")
struct TranscriptWatcherTests {
    private let sessionID = "11111111-1111-4111-8111-111111111111"
    private let projects: TemporaryProjects
    private let watcher: TranscriptWatcher

    init() throws {
        projects = try TemporaryProjects()
        watcher = TranscriptWatcher(projectsDirectory: projects.root, now: { TestClock.at(200) })
    }

    private func digest(in events: [SessionEvent]) throws -> TranscriptDigest {
        let event = try #require(events.first)
        guard case .transcriptActivity(let digest) = event.signal else {
            throw CocoaError(.coderInvalidValue)
        }
        return digest
    }

    @Test("The launch scan reports each recent session with its digest and path")
    func scanAll() async throws {
        let path = try projects.write(Fixture.running.data, sessionID: sessionID, modified: TestClock.at(40))

        let events = await watcher.scanAll()

        #expect(events.count == 1)
        #expect(events.first?.sessionID == sessionID)
        #expect(events.first?.date == TestClock.at(200))
        #expect(events.first?.transcriptPath == path)
        #expect(try digest(in: events) == Fixture.running.digest)
    }

    @Test("The launch scan skips transcripts untouched for more than 24 hours, but reads them when they change")
    func oldTranscripts() async throws {
        let dayAgo = TestClock.at(200 - 24 * TestClock.hour - 1)
        let path = try projects.write(Fixture.done.data, sessionID: sessionID, modified: dayAgo)

        #expect(await watcher.scanAll().isEmpty)

        let events = await watcher.scan(paths: [path])
        #expect(try digest(in: events) == Fixture.done.digest)
    }

    @Test("Only the bytes appended since the last read are parsed")
    func appendedBytes() async throws {
        let data = try Fixture.done.data
        let split = try #require(data.firstIndex(of: UInt8(ascii: "\n"))) + 1
        let path = try projects.write(data[..<split], sessionID: sessionID)

        let first = try digest(in: await watcher.scan(paths: [path]))
        #expect(first.counts == ActivityCounts(userTurns: 1, toolCalls: 0))

        try projects.append(data[split...], toPath: path)
        let second = try digest(in: await watcher.scan(paths: [path]))
        // Equal to a single full parse: nothing was read twice and nothing was dropped.
        #expect(second == (try Fixture.done.digest))
    }

    @Test("A change notification with nothing new produces no event")
    func unchangedFile() async throws {
        let path = try projects.write(Fixture.quick.data, sessionID: sessionID)
        _ = await watcher.scan(paths: [path])

        #expect(await watcher.scan(paths: [path]).isEmpty)
    }

    @Test("A line still being written is held until its newline arrives")
    func partialLine() async throws {
        let data = try Fixture.quick.data
        let cut = data.count - 20
        let path = try projects.write(data[..<cut], sessionID: sessionID)

        let partial = try digest(in: await watcher.scan(paths: [path]))
        #expect(partial.counts.userTurns == 1)
        #expect(partial.lastActivityAt == TestClock.start)

        try projects.append(data[cut...], toPath: path)
        #expect(try digest(in: await watcher.scan(paths: [path])) == Fixture.quick.digest)
    }

    @Test("A truncated file is read again from the start")
    func truncatedFile() async throws {
        let path = try projects.write(Fixture.done.data, sessionID: sessionID)
        _ = await watcher.scan(paths: [path])

        try Fixture.quick.data.write(to: URL(fileURLWithPath: path))

        #expect(try digest(in: await watcher.scan(paths: [path])) == Fixture.quick.digest)
    }

    @Test("A file replaced by a longer one is read again from the start")
    func replacedFile() async throws {
        let path = try projects.write(Fixture.quick.data, sessionID: sessionID)
        _ = await watcher.scan(paths: [path])

        try FileManager.default.removeItem(atPath: path)
        try projects.write(Fixture.done.data, to: projects.project.appending(path: "replacement.tmp"))
        try FileManager.default.moveItem(atPath: projects.project.appending(path: "replacement.tmp").path, toPath: path)

        #expect(try digest(in: await watcher.scan(paths: [path])) == Fixture.done.digest)
    }

    @Test("A subagent transcript reports activity for its parent session and creates no session of its own")
    func subagentTranscript() async throws {
        let url = projects.project.appending(path: "\(sessionID)/subagents/agent-a1b2c3.jsonl")
        let path = try projects.write(Fixture.running.data, to: url, modified: TestClock.at(150))

        let events = await watcher.scan(paths: [path])

        #expect(events == [
            SessionEvent(sessionID: sessionID, date: TestClock.at(200), signal: .subagentTranscriptActivity(TestClock.at(150)))
        ])
        #expect(await watcher.scanAll().isEmpty)
    }

    @Test("Files that are not session transcripts are ignored", arguments: [
        "notes.jsonl",
        "11111111-1111-4111-8111-111111111111.orphaned-1794650400-ab12.jsonl",
        "11111111-1111-4111-8111-111111111111.jsonl.superseded-1794650400",
        "11111111-1111-4111-8111-111111111111.json",
        "nested/deeper/11111111-1111-4111-8111-111111111111.jsonl",
        "11111111-1111-4111-8111-111111111111/tool-results/output.jsonl",
    ])
    func ignoredFiles(name: String) async throws {
        let path = try projects.write(Fixture.done.data, to: projects.project.appending(path: name))

        #expect(await watcher.scan(paths: [path]).isEmpty)
        #expect(await watcher.scanAll().isEmpty)
    }

    @Test("A transcript with no conversation yet produces no event")
    func metadataOnlyTranscript() async throws {
        let line = #"{"type":"queue-operation","operation":"enqueue","sessionId":"s","timestamp":"2026-11-14T10:00:00.000Z"}"# + "\n"
        let path = try projects.write(Data(line.utf8), sessionID: sessionID)

        #expect(await watcher.scan(paths: [path]).isEmpty)
    }

    @Test("A transcript a hook names outside the projects directory is read, and read again as it grows")
    func externalTranscript() async throws {
        let outside = projects.root.deletingLastPathComponent().appending(path: "broom-outside-\(UUID().uuidString)/\(sessionID).jsonl")
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        let data = try Fixture.done.data
        let split = try #require(data.firstIndex(of: UInt8(ascii: "\n"))) + 1
        let path = try projects.write(data[..<split], to: outside)

        await watcher.register(sessionID: sessionID, transcriptPath: path)
        // Registering twice, or registering a path that is already watched, adds nothing.
        #expect(await watcher.register(sessionID: sessionID, transcriptPath: path) == nil)
        #expect(await watcher.scanExternal().isEmpty)

        try projects.append(data[split...], toPath: path)
        let events = await watcher.scanExternal()

        #expect(events.count == 1)
        #expect(events.first?.sessionID == sessionID)
        #expect(events.first?.transcriptPath == path)
        #expect(try digest(in: events) == Fixture.done.digest)
    }

    @Test("Registering an outside transcript returns what it holds, so the bytes read are not lost before the stream runs")
    func registerReturnsFirstRead() async throws {
        let outside = projects.root.deletingLastPathComponent().appending(path: "broom-outside-\(UUID().uuidString)/\(sessionID).jsonl")
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        let path = try projects.write(Fixture.done.data, to: outside)

        let event = await watcher.register(sessionID: sessionID, transcriptPath: path)

        #expect(event?.sessionID == sessionID)
        #expect(event?.transcriptPath == path)
        #expect(try digest(in: [event].compactMap { $0 }) == Fixture.done.digest)
        #expect(await watcher.scanExternal().isEmpty)
    }

    @Test("Registering a path inside the projects directory changes nothing: it is already watched")
    func registerWatchedPath() async throws {
        let path = try projects.write(Fixture.quick.data, sessionID: sessionID)

        await watcher.register(sessionID: sessionID, transcriptPath: path)

        #expect(await watcher.scanExternal().isEmpty)
        #expect(await watcher.scan(paths: [path]).count == 1)
    }

    @Test("A deleted file produces no event")
    func deletedFile() async throws {
        let path = try projects.write(Fixture.quick.data, sessionID: sessionID)
        _ = await watcher.scan(paths: [path])
        try FileManager.default.removeItem(atPath: path)

        #expect(await watcher.scan(paths: [path]).isEmpty)
    }

    @Test("The event stream reports the launch scan, then a session written afterwards", .tags(.integration), .timeLimit(.minutes(1)))
    func eventStream() async throws {
        let existing = "22222222-2222-4222-8222-222222222222"
        try projects.write(Fixture.quick.data, sessionID: existing, modified: TestClock.at(100))
        var seen: [String] = []

        var liveDigest: TranscriptDigest?

        for await event in watcher.events() {
            seen.append(event.sessionID)
            if event.sessionID == existing {
                // The launch scan has run, so the file-system watch is already active.
                try projects.write(Fixture.done.data, sessionID: sessionID)
            } else if case .transcriptActivity(let digest) = event.signal, digest.lastActivityAt == TestClock.at(100) {
                // The whole file has been read (its last line is at +100 s).
                liveDigest = digest
                break
            }
        }

        #expect(seen.first == existing)
        #expect(seen.dropFirst().allSatisfy { $0 == sessionID })
        #expect(try liveDigest == Fixture.done.digest)
    }

    @Test("A projects directory created after launch is picked up", .tags(.integration), .timeLimit(.minutes(1)))
    func directoryCreatedLater() async throws {
        let missing = projects.root.appending(path: "not-yet/projects")
        let lateWatcher = TranscriptWatcher(projectsDirectory: missing, now: { TestClock.at(200) })
        let stream = lateWatcher.events()

        // Keep writing until the watcher, which starts asynchronously, reports the session.
        let writer = Task {
            var lines = 0
            while !Task.isCancelled {
                let url = missing.appending(path: "-Users-dev/\(sessionID).jsonl")
                lines += 1
                let line = #"{"type":"user","timestamp":"2026-11-14T10:00:00.000Z","message":{"role":"user","content":"line \#(lines)"}}"# + "\n"
                if lines == 1 {
                    _ = try? projects.write(Data(line.utf8), to: url)
                } else {
                    try? projects.append(Data(line.utf8), toPath: url.path)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { writer.cancel() }

        var reported: String?
        for await event in stream {
            reported = event.sessionID
            break
        }

        #expect(reported == sessionID)
    }
}
