import Foundation
import Testing
@testable import BroomCore

@Suite("TranscriptParser")
struct TranscriptParserTests {
    @Test("A mid-turn transcript counts only main-agent turns and tools")
    func running() throws {
        let digest = try Fixture.running.digest

        #expect(digest.sessionID == "11111111-1111-4111-8111-111111111111")
        #expect(digest.cwd == "/Users/dev/code/acme-api")
        #expect(digest.counts == ActivityCounts(userTurns: 1, toolCalls: 2))
        #expect(digest.startedAt == TestClock.start)
        #expect(digest.tail == .other)
        #expect(digest.progress == nil)
        #expect(digest.malformedLineCount == 0)
    }

    @Test("Subagent lines move last activity but nothing else")
    func subagentLinesCountTowardLiveness() throws {
        let digest = try Fixture.running.digest

        // The last main-agent line is at +33 s; the subagent's tool call is at +40 s.
        #expect(digest.lastActivityAt == TestClock.at(40))
    }

    @Test("The title is the first prompt, whitespace collapsed and cut to 60 characters")
    func promptTitle() throws {
        let title = try #require(try Fixture.running.digest.title)

        #expect(title == "Refactor the billing module to use the new invoice API and …")
        #expect(title.count == 60)
    }

    @Test("A short prompt is used as the title unchanged")
    func shortPromptTitle() throws {
        #expect(try Fixture.waitingPermission.digest.title == "Delete the stale build artifacts")
    }

    @Test("A tool call with no result leaves a pending-tool tail")
    func waitingPermission() throws {
        let digest = try Fixture.waitingPermission.digest

        #expect(digest.tail == .pendingTool(name: "Bash"))
        #expect(digest.counts == ActivityCounts(userTurns: 1, toolCalls: 1))
        #expect(digest.lastActivityAt == TestClock.at(4))
    }

    @Test("Assistant text ending in a question mark leaves a question tail")
    func waitingQuestion() throws {
        let digest = try Fixture.waitingQuestion.digest

        #expect(digest.tail == .assistantQuestion(
            "I found two configured databases.\n\nWhich one should I target, staging or production?"
        ))
        #expect(digest.counts.toolCalls == 1)
    }

    @Test("A finished transcript takes the latest custom title and skips harness lines")
    func done() throws {
        let digest = try Fixture.done.digest

        #expect(digest.title == "Fix flaky login test")
        // The `<local-command-stdout>` and `isMeta` user lines are not turns.
        #expect(digest.counts == ActivityCounts(userTurns: 2, toolCalls: 3))
        #expect(digest.firstPrompt == "The login test is flaky, find out why")
        #expect(digest.tail == .other)
        #expect(digest.lastActivityAt == TestClock.at(100))
    }

    @Test("A one-question transcript has one turn and no tools")
    func quick() throws {
        let digest = try Fixture.quick.digest

        #expect(digest.counts == ActivityCounts(userTurns: 1, toolCalls: 0))
        #expect(digest.tail == .other)
        #expect(digest.lastActivityAt == TestClock.at(6))
    }

    @Test("Malformed and unknown lines are skipped without losing the good ones")
    func malformed() throws {
        let digest = try Fixture.malformed.digest

        // Not JSON, cut-off JSON, and a JSON array. Blank lines and unknown types are not errors.
        #expect(digest.malformedLineCount == 3)
        #expect(digest.counts == ActivityCounts(userTurns: 1, toolCalls: 0))
        #expect(digest.firstPrompt == "Summarise the README")
        #expect(digest.startedAt == TestClock.start)
        #expect(digest.lastActivityAt == TestClock.at(9))
        #expect(digest.tail == .other)
    }

    @Test("A trailing partial line waits for its newline")
    func partialLine() throws {
        let data = try Fixture.malformed.data
        var parser = TranscriptParser()

        parser.consume(data)
        let partialLength = try #require(data.split(separator: UInt8(ascii: "\n")).last?.count)
        #expect(parser.consumedByteCount == data.count - partialLength)
        #expect(parser.digest.counts.userTurns == 1)

        parser.consume(Data(#""}}"#.utf8) + Data("\n".utf8))
        #expect(parser.consumedByteCount == data.count + 4)
        #expect(parser.digest.counts.userTurns == 2)
        #expect(parser.digest.malformedLineCount == 3)
    }

    @Test("Feeding a file byte by byte gives the same digest as one chunk", arguments: Fixture.allCases)
    func chunking(fixture: Fixture) throws {
        let data = try fixture.data
        var parser = TranscriptParser()

        for byte in data {
            parser.consume(Data([byte]))
        }

        #expect(try parser.digest == fixture.digest)
    }

    @Test("The latest TodoWrite call gives the progress")
    func todoWriteProgress() throws {
        let digest = try Fixture.progressTodoWrite.digest

        #expect(digest.progress == StepProgress(completed: 3, total: 4))
        #expect(digest.counts.toolCalls == 2)
    }

    @Test("TaskCreate and TaskUpdate calls replay into progress")
    func taskProgress() throws {
        let digest = try Fixture.progressTasks.digest

        // Created: #1, #2, #7, a failed create, #8. Then #1 completed, #2 deleted, an update to unknown #99.
        #expect(digest.progress == StepProgress(completed: 1, total: 3))
        #expect(digest.tail == .other)
    }

    @Test("Task ids that run ahead of the creation order are not lost")
    func taskIDsAheadOfCreationOrder() {
        var parser = TranscriptParser()
        parser.consume(lines([
            assistantTool(id: "c1", name: "TaskCreate", input: #"{"subject":"a"}"#),
            toolResult(id: "c1", content: "Task #2 created successfully"),
            assistantTool(id: "c2", name: "TaskCreate", input: #"{"subject":"b"}"#),
            toolResult(id: "c2", content: "Task #3 created successfully"),
            assistantTool(id: "u1", name: "TaskUpdate", input: #"{"taskId":"2","status":"completed"}"#),
        ]))

        #expect(parser.digest.progress == StepProgress(completed: 1, total: 2))
    }

    @Test("Tasks created in parallel count before their results arrive")
    func parallelTaskCreates() {
        var parser = TranscriptParser()
        parser.consume(lines([
            assistantTool(id: "c1", name: "TaskCreate", input: #"{"subject":"a"}"#),
            assistantTool(id: "c2", name: "TaskCreate", input: #"{"subject":"b"}"#),
        ]))
        #expect(parser.digest.progress == StepProgress(completed: 0, total: 2))

        parser.consume(lines([
            toolResult(id: "c2", content: "Task #2 created successfully"),
            toolResult(id: "c1", content: "Task #1 created successfully"),
            assistantTool(id: "u1", name: "TaskUpdate", input: #"{"taskId":2,"status":"completed"}"#),
        ]))
        #expect(parser.digest.progress == StepProgress(completed: 1, total: 2))
    }

    @Test("A user line carrying both a tool result and prompt text is a turn")
    func mixedToolResultAndPrompt() {
        var parser = TranscriptParser()
        parser.consume(lines([
            assistantTool(id: "t1", name: "Bash", input: "{}"),
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"},{"type":"text","text":"also do X"}]}}"#,
        ]))

        #expect(parser.digest.counts.userTurns == 1)
        #expect(parser.digest.firstPrompt == "also do X")
        #expect(parser.digest.tail == .other)
    }

    @Test("A new prompt clears a tool call that never got a result")
    func newPromptClearsAbandonedToolCall() {
        var parser = TranscriptParser()
        parser.consume(lines([
            assistantTool(id: "t1", name: "Bash", input: "{}"),
            #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user for tool use]"}}"#,
        ]))
        // The interrupt ends the turn: the tool call is no longer pending and the line is not a prompt.
        #expect(parser.digest.tail == .interrupted)
        #expect(parser.digest.counts.userTurns == 0)

        parser.consume(lines([
            #"{"type":"user","message":{"role":"user","content":"next"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sure."}]}}"#,
        ]))
        #expect(parser.digest.tail == .other)
    }

    @Test("An interrupt records its own time, not the time of later lines")
    func interruptTime() {
        var parser = TranscriptParser()
        parser.consume(lines([
            #"{"type":"user","timestamp":"2026-11-14T10:00:20.000Z","message":{"role":"user","content":"[Request interrupted by user]"}}"#,
            #"{"type":"system","subtype":"note","timestamp":"2026-11-14T10:00:45.000Z"}"#,
        ]))

        #expect(parser.digest.interruptedAt == TestClock.at(20))
        #expect(parser.digest.lastActivityAt == TestClock.at(45))
        #expect(parser.digest.tail == .interrupted)
    }

    @Test("Parallel tool calls stay pending until every result is in")
    func parallelToolCalls() {
        var parser = TranscriptParser()
        parser.consume(lines([
            assistantTool(id: "t1", name: "Read", input: "{}"),
            assistantTool(id: "t2", name: "Bash", input: "{}"),
            toolResult(id: "t2", content: "ok"),
        ]))
        #expect(parser.digest.tail == .pendingTool(name: "Read"))

        parser.consume(lines([toolResult(id: "t1", content: "ok")]))
        #expect(parser.digest.tail == .other)
        #expect(parser.digest.counts.toolCalls == 2)
    }

    @Test("A timestamp on any line type moves last activity; only conversation lines set the start")
    func timestampsOnMetadataLines() {
        var parser = TranscriptParser()
        parser.consume(lines([
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-11-14T09:59:00.000Z"}"#,
            #"{"type":"user","timestamp":"2026-11-14T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-11-14T10:00:50.000Z"}"#,
            #"{"type":"custom-title","customTitle":"No timestamp here"}"#,
        ]))

        #expect(parser.digest.startedAt == TestClock.start)
        #expect(parser.digest.lastActivityAt == TestClock.at(50))
    }

    @Test("A 50,000-line transcript in one chunk parses in linear time", .timeLimit(.minutes(1)))
    func largeTranscript() {
        let line = #"{"type":"assistant","timestamp":"2026-11-14T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Read","input":{}}]}}"# + "\n"
        var parser = TranscriptParser()

        parser.consume(Data(String(repeating: line, count: 50_000).utf8))

        #expect(parser.digest.counts.toolCalls == 50_000)
        #expect(parser.consumedByteCount == line.utf8.count * 50_000)
    }

    @Test("Multi-byte text split across chunks and CRLF line endings parse correctly")
    func splitUTF8AndCRLF() {
        let bytes = Array((#"{"type":"user","message":{"role":"user","content":"Añade café ☕ al menú"}}"# + "\r\n").utf8)
        var parser = TranscriptParser()

        for chunk in stride(from: 0, to: bytes.count, by: 3) {
            parser.consume(Data(bytes[chunk..<min(chunk + 3, bytes.count)]))
        }

        #expect(parser.digest.firstPrompt == "Añade café ☕ al menú")
        #expect(parser.consumedByteCount == bytes.count)
        #expect(parser.digest.malformedLineCount == 0)
    }

    @Test("Wrong value types are ignored without crashing")
    func wrongValueTypes() {
        var parser = TranscriptParser()
        parser.consume(lines([
            #"{"type":"user","timestamp":12345,"cwd":7,"isSidechain":"no","message":{"role":"user","content":null}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":5,"name":null},{"type":"text","text":9},null]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"TodoWrite","input":{"todos":"none"}}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"TaskUpdate","input":{"taskId":null,"status":4}}]}}"#,
            #"{"type":"custom-title","customTitle":42}"#,
            #"{"type":7}"#,
        ]))

        #expect(parser.digest.malformedLineCount == 0)
        #expect(parser.digest.counts == ActivityCounts(userTurns: 0, toolCalls: 2))
        #expect(parser.digest.progress == nil)
        #expect(parser.digest.title == nil)
    }

    @Test("Reset forgets everything")
    func reset() throws {
        var parser = TranscriptParser()
        try parser.consume(Fixture.done.data)

        parser.reset()

        #expect(parser.digest == TranscriptDigest())
        #expect(parser.consumedByteCount == 0)
    }

    @Test("Metadata lines that repeat message content are not counted")
    func metadataLinesIgnored() {
        var parser = TranscriptParser()
        let blob = #"{"type":"api-request-blob","sessionId":"s","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#

        parser.consume(Data((blob + "\n").utf8))

        #expect(parser.digest.counts == ActivityCounts())
        #expect(parser.digest.tail == .other)
        #expect(parser.digest.lastActivityAt == nil)
    }

    @Test("Timestamps parse with and without fractional seconds", arguments: [
        "2026-11-14T10:00:07.000Z", "2026-11-14T10:00:07Z",
    ])
    func timestamps(timestamp: String) {
        var parser = TranscriptParser()
        let line = #"{"type":"user","timestamp":"\#(timestamp)","message":{"role":"user","content":"hi"}}"#

        parser.consume(Data((line + "\n").utf8))

        #expect(parser.digest.lastActivityAt == TestClock.at(7))
    }

    // MARK: Line builders

    private func lines(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func assistantTool(id: String, name: String, input: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
    }

    private func toolResult(id: String, content: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"\#(content)"}]}}"#
    }

    @Test("An older summary line is used as the title until a custom title appears")
    func summaryLine() {
        var parser = TranscriptParser()

        parser.consume(Data(#"{"type":"summary","summary":"Old style title"}"#.utf8) + Data("\n".utf8))
        #expect(parser.digest.title == "Old style title")

        parser.consume(Data(#"{"type":"custom-title","customTitle":"New title"}"#.utf8) + Data("\n".utf8))
        #expect(parser.digest.title == "New title")
    }
}
