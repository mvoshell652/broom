import Testing
@testable import BroomCore

@Suite("TranscriptFile")
struct TranscriptFileTests {
    private let root = "/Users/dev/.claude/projects"
    private let id = "11111111-1111-4111-8111-111111111111"

    @Test("A UUID-named file one level down is a session")
    func session() {
        #expect(TranscriptFile(path: "\(root)/-Users-dev-code/\(id).jsonl", projectsDirectory: root) == .session(id: id))
        #expect(TranscriptFile(path: "\(root)/-Users-dev-code/\(id).jsonl", projectsDirectory: root + "/") == .session(id: id))
    }

    @Test("A file in a session's subagents folder belongs to that session")
    func subagent() {
        let path = "\(root)/-Users-dev-code/\(id)/subagents/agent-7.jsonl"

        #expect(TranscriptFile(path: path, projectsDirectory: root) == .subagent(parentSessionID: id))
    }

    @Test("Paths outside the projects directory or at the wrong depth are not transcripts", arguments: [
        "/Users/dev/.claude/projects-other/p/11111111-1111-4111-8111-111111111111.jsonl",
        "/Users/dev/.claude/projects/11111111-1111-4111-8111-111111111111.jsonl",
        "/Users/dev/.claude/projects/p/q/11111111-1111-4111-8111-111111111111.jsonl",
        "/Users/dev/.claude/projects/p/not-a-uuid/subagents/agent-7.jsonl",
        "/Users/dev/.claude/projects/p/11111111-1111-4111-8111-111111111111/other/agent-7.jsonl",
    ])
    func notTranscripts(path: String) {
        #expect(TranscriptFile(path: path, projectsDirectory: root) == nil)
    }
}
