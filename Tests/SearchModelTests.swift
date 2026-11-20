import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("SearchModel")
@MainActor
struct SearchModelTests {
    private let store: ChatIndexStore
    private let model: SearchModel

    init() throws {
        store = try ChatIndexStore()
        for (id, title, reply) in [("a", "RLS policies", "Use one policy per table."), ("b", "Pace maths", "A 22 minute 5K is about 7:05 per mile."), ("c", "More pace", "Negative splits keep the pace even.")] {
            let chat = IndexedChat(id: id, title: title, hasCustomTitle: true, transcriptPath: "/tmp/\(id).jsonl")
            try store.save(chat, adding: [ChatTurn(role: .assistant, text: reply)], fileNumber: 1, offset: 1)
        }
        model = SearchModel(store: store, projectsDirectory: nil, embedder: nil)
    }

    @Test("Typing a query fills the results and selects the first")
    func results() async {
        model.query = "pace"

        await model.updateResults()

        #expect(Set(model.results.map(\.id)) == ["b", "c"])
        #expect(model.selectedID == model.results.first?.id)
        #expect(model.indexedCount == 3)
    }

    @Test("The arrow keys move through the results and stop at either end")
    func selection() async {
        model.query = "pace"
        await model.updateResults()
        let ids = model.results.map(\.id)

        model.moveSelection(by: 1)
        let second = model.selectedID
        model.moveSelection(by: 1)
        let pastEnd = model.selectedID
        model.moveSelection(by: -5)

        #expect(second == ids[1])
        #expect(pastEnd == ids[1])
        #expect(model.selectedID == ids[0])
    }

    @Test("A query that changed while searching does not show the older results")
    func staleQuery() async {
        model.query = "pace"
        let search = Task { await model.updateResults() }
        // Let the search read the query and start waiting, then change the query under it.
        await Task.yield()
        model.query = "policy"
        await search.value

        #expect(model.results.isEmpty)
    }

    @Test("Showing the window starts from an empty field")
    func presenting() async {
        model.query = "pace"
        await model.updateResults()

        model.willPresent()

        #expect(model.query.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.selectedID == nil)
        #expect(model.presentationCount == 1)
    }

    @Test("Deleting the index empties it")
    func deleting() async throws {
        await model.deleteIndex()

        #expect(model.indexedCount == 0)
        #expect(try store.chatCount() == 0)
        #expect(try store.textMatches(for: "pace", limit: 5).isEmpty)
    }

    @Test("The indexer run by the model reads transcripts into the index")
    func indexing() async throws {
        let projects = try TemporaryProjects()
        let id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        try projects.write(TranscriptLine.user("How do I rotate a Supabase key?", session: id), sessionID: id)
        let store = try ChatIndexStore()
        let model = SearchModel(store: store, projectsDirectory: projects.root, embedder: nil)

        let indexing = Task { await model.runIndexing() }
        let indexed = await eventually { model.indexedCount == 1 }
        indexing.cancel()
        await indexing.value

        #expect(indexed)
        #expect(model.isIndexing == false)
        #expect(try store.chat(id: id)?.title == "How do I rotate a Supabase key?")
    }
}
