import Foundation
import NaturalLanguage
import Testing
@testable import BroomCore

@Suite("Chat index")
struct ChatIndexTests {
    private let projects: TemporaryProjects
    private let store: ChatIndexStore
    private let a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let b = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    /// "rls" and "security" are one topic, "pace" and "running" another.
    private let embedder = KeywordEmbedder(topics: [["rls", "security", "policies"], ["pace", "running", "mile"]])

    init() throws {
        projects = try TemporaryProjects()
        store = try ChatIndexStore()
    }

    private func indexer() -> ChatIndexer {
        ChatIndexer(projectsDirectory: projects.root, store: store, embedder: embedder)
    }

    // MARK: - Reading text

    @Test("Prompts and replies are kept; tool calls, tool output, commands and interruptions are not")
    func readerKeepsConversation() {
        let data = TranscriptLine.user("How do I write RLS policies?", session: a, at: 0)
            + TranscriptLine.assistant("Start with a policy per table.", session: a, at: 5, toolCommand: "psql -c 'select secret'")
            + TranscriptLine.toolResult("secret-output", session: a, at: 5)
            + TranscriptLine.user("<command-name>/clear</command-name>", session: a, at: 6)
            + TranscriptLine.user("[Request interrupted by user]", session: a, at: 7)
            + TranscriptLine.user("meta line", session: a, at: 8, isMeta: true)

        let batch = TranscriptTextReader.read(data)

        #expect(batch.turns.map(\.role) == [.user, .assistant])
        #expect(batch.turns.map(\.text) == ["How do I write RLS policies?", "Start with a policy per table."])
        #expect(batch.cwd == "/Users/dev/code/acme-api")
        #expect(batch.consumedByteCount == data.count)
    }

    @Test("A line still being written is left for the next read")
    func readerLeavesPartialLine() {
        let complete = TranscriptLine.user("First prompt", session: a)
        let partial = TranscriptLine.user("Second prompt", session: a).dropLast(10)

        let batch = TranscriptTextReader.read(complete + partial)

        #expect(batch.turns.map(\.text) == ["First prompt"])
        #expect(batch.consumedByteCount == complete.count)
    }

    @Test("Long turns are cut to the index's limit")
    func readerTruncates() {
        let batch = TranscriptTextReader.read(TranscriptLine.user(String(repeating: "x", count: 9000), session: a))

        #expect(batch.turns.first?.text.count == TranscriptTextReader.maximumTurnLength)
    }

    @Test("The fixture transcripts yield their conversation", arguments: [Fixture.quick, .done, .waitingQuestion])
    func readerOnFixtures(fixture: Fixture) throws {
        let batch = TranscriptTextReader.read(try fixture.data)

        #expect(batch.turns.first?.role == .user)
        #expect(batch.turns.contains { $0.role == .assistant })
    }

    // MARK: - Indexing

    @Test("A chat is titled from its first prompt, and a custom title replaces that")
    func titles() async throws {
        try projects.write(TranscriptLine.user("How do I write RLS policies?", session: a), sessionID: a)
        try projects.write(
            TranscriptLine.user("Convert 5K pace", session: b) + TranscriptLine.customTitle("Pace maths", session: b), sessionID: b
        )

        try await indexer().indexAll()

        #expect(try store.chat(id: a)?.title == "How do I write RLS policies?")
        #expect(try store.chat(id: b)?.title == "Pace maths")
        #expect(try store.chat(id: b)?.firstPrompt == "Convert 5K pace")
        #expect(try store.chatCount() == 2)
    }

    @Test("Indexing again adds nothing; appended lines add only themselves")
    func incremental() async throws {
        let path = try projects.write(
            TranscriptLine.user("How do I write RLS policies?", session: a, at: 0)
                + TranscriptLine.assistant("Start with a policy per table.", session: a, at: 5),
            sessionID: a
        )
        let indexer = indexer()

        let first = try await indexer.indexAll()
        let second = try await indexer.indexAll()
        try projects.append(TranscriptLine.user("And for teams?", session: a, at: 60), toPath: path)
        let third = try await indexer.indexAll()

        #expect(first.turnsAdded == 2)
        #expect(first.chatsEmbedded == 1)
        #expect(second == IndexSummary())
        #expect(!second.hasChanges)
        #expect(first.hasChanges && third.hasChanges)
        #expect(third.turnsAdded == 1)
        let chat = try #require(try store.chat(id: a))
        #expect(chat.turnCount == 3)
        #expect(chat.lastTurnText == "And for teams?")
        #expect(chat.lastTurnRole == .user)
        #expect(chat.startedAt == TestClock.at(0))
        #expect(chat.lastActivityAt == TestClock.at(60))
    }

    @Test("A transcript that was replaced is indexed again from the start, without leaving old text behind")
    func replacedFile() async throws {
        let path = try projects.write(TranscriptLine.user("Old question about pace", session: a), sessionID: a)
        let indexer = indexer()
        try await indexer.indexAll()

        try FileManager.default.removeItem(atPath: path)
        try projects.write(TranscriptLine.user("New question about RLS", session: a), sessionID: a)
        let summary = try await indexer.indexAll()

        #expect(summary.filesReset == 1)

        #expect(try store.chat(id: a)?.turnCount == 1)
        #expect(try store.textMatches(for: "pace", limit: 5).isEmpty)
        #expect(try store.textMatches(for: "RLS", limit: 5).map(\.chatID) == [a])
    }

    @Test("Files that are not session transcripts are ignored")
    func ignoresOtherFiles() async throws {
        try projects.write(TranscriptLine.user("Subagent work", session: a), to: projects.project.appending(path: "\(a)/subagents/agent-1.jsonl"))
        try projects.write(Data("not json\n".utf8), to: projects.project.appending(path: "notes.jsonl"))

        let summary = try await indexer().indexAll()

        #expect(summary == IndexSummary())
        #expect(try store.chatCount() == 0)
    }

    // MARK: - Search

    @Test("A search finds a chat by a word in a reply and shows the passage")
    func searchByWords() async throws {
        try projects.write(
            TranscriptLine.user("Help with the matching engine", session: a)
                + TranscriptLine.assistant("We settled on weighting compatibility at 0.4 and division at 0.3.", session: a, at: 5),
            sessionID: a
        )
        try await indexer().indexAll()

        let results = try ChatSearch(store: store, embedder: embedder).results(for: "weighting division")

        #expect(results.map(\.id) == [a])
        #expect(results.first?.snippet?.contains("weighting") == true)
    }

    @Test("A search finds a chat by meaning when no word matches")
    func searchByMeaning() async throws {
        try projects.write(TranscriptLine.user("How do I write RLS policies?", session: a), sessionID: a)
        try projects.write(TranscriptLine.user("Convert 5K pace", session: b), sessionID: b)
        try await indexer().indexAll()

        let results = try ChatSearch(store: store, embedder: embedder).results(for: "security")

        #expect(results.map(\.id) == [a])
        #expect(results.first?.snippet == nil)
    }

    @Test("A chat that matches both the words and the meaning comes first")
    func searchFusion() async throws {
        try projects.write(TranscriptLine.user("Notes on running shoes", session: a), sessionID: a)
        try projects.write(TranscriptLine.user("What pace for a mile?", session: b), sessionID: b)
        try await indexer().indexAll()

        let results = try ChatSearch(store: store, embedder: embedder).results(for: "mile pace")

        #expect(results.map(\.id) == [b, a])
    }

    @Test("An empty or punctuation-only query finds nothing", arguments: ["", "   ", "?!"])
    func searchEmpty(query: String) throws {
        #expect(try ChatSearch(store: store, embedder: embedder).results(for: query).isEmpty)
    }

    // MARK: - Vectors

    @Test("Vectors survive storage, and identical ones are fully alike")
    func vectors() {
        let vector: [Float] = [0.25, -1.5, 3]

        #expect(VectorMath.vector(from: VectorMath.data(from: vector)) == vector)
        #expect(abs(VectorMath.cosineSimilarity(vector, vector) - 1) < 0.0001)
        #expect(VectorMath.cosineSimilarity(vector, [1, 2]) == 0)
        #expect(VectorMath.cosineSimilarity([0, 0], [0, 0]) == 0)
    }

    @Test(
        "The on-device embedding puts related sentences closer than unrelated ones",
        .enabled(if: NLEmbedding.sentenceEmbedding(for: .english) != nil, "Needs the on-device English sentence embedding")
    )
    func naturalLanguageEmbedder() throws {
        let embedder = NaturalLanguageEmbedder()
        let question = try #require(embedder.vector(for: "How should I write Supabase RLS policies for teams?"))
        let related = try #require(embedder.vector(for: "Row-level security in Supabase scoped to an organisation"))
        let unrelated = try #require(embedder.vector(for: "Ideas for an announcement post about the Chicago race"))

        #expect(VectorMath.cosineSimilarity(question, related) > VectorMath.cosineSimilarity(question, unrelated))
        #expect(embedder.vector(for: "   ") == nil)
    }
}
