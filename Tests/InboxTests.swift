import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("Inbox")
struct InboxTests {
    private let store: WorkstreamStore
    private let index: ChatIndexStore
    private let library: WorkstreamLibrary
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 3600

    init() throws {
        store = try WorkstreamStore()
        index = try ChatIndexStore()
        library = WorkstreamLibrary(store: store, index: index)
    }

    private func chat(
        _ id: String, cwd: String? = "/code/api", ago: TimeInterval = 3600, last: (ChatRole, String)? = nil
    ) -> IndexedChat {
        IndexedChat(
            id: id, title: id, cwd: cwd, lastTurnText: last?.1, lastTurnRole: last?.0,
            startedAt: now.addingTimeInterval(-ago - 60), lastActivityAt: now.addingTimeInterval(-ago), transcriptPath: "/tmp/\(id)"
        )
    }

    /// Adds a chat to the index with the vector and opening it is compared by.
    @discardableResult
    private func add(_ chat: IndexedChat, vector: [Float]? = nil, opening: String? = nil) throws -> IndexedChat {
        try index.save(chat, adding: [], fileNumber: 0, offset: 0)
        if let vector { try index.saveEmbedding(vector, of: opening ?? chat.id, forChat: chat.id) }
        return chat
    }

    // MARK: - Duplicates

    @Test("Chats that open with the same prompt are one group, however many there are")
    func identicalOpenings() {
        let chats = (1...7).map { chat("c\($0)", ago: Double($0) * 3600) }
        let openings = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, "Run the daily batch") })

        let groups = DuplicateFinder.groups(among: chats, vectors: [:], openings: openings, now: now)

        #expect(groups.count == 1)
        #expect(groups.first?.kind == .identical)
        #expect(groups.first?.chats.map(\.id) == chats.map(\.id))
        #expect(groups.first?.topic == "c1")
    }

    @Test("Chats with nearly the same meaning are a group; ones that are merely related are not")
    func similarOpenings() {
        let chats = [chat("a"), chat("b", ago: 7200), chat("c", ago: 9000)]
        let vectors: [String: [Float]] = ["a": [1, 0], "b": [1, 0.2], "c": [0.6, 0.8]]

        let groups = DuplicateFinder.groups(among: chats, vectors: vectors, openings: ["a": "one", "b": "two", "c": "three"], now: now)

        #expect(groups.map { $0.chats.map(\.id) } == [["a", "b"]])
        #expect(groups.first?.kind == .similar)
    }

    @Test("More than five similar chats are a shared preamble, not duplicates")
    func largeSimilarGroup() {
        let chats = (1...6).map { chat("c\($0)", ago: Double($0) * 3600) }
        let vectors = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, [Float(1), 0]) })
        let openings = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, "opening \($0.id)") })

        #expect(DuplicateFinder.groups(among: chats, vectors: vectors, openings: openings, now: now).isEmpty)
    }

    @Test("Chats over 30 days quiet, already merged together, or marked not the same are not raised")
    func exclusions() {
        let chats = [chat("a"), chat("b"), chat("old", ago: 31 * day), chat("m1"), chat("m2"), chat("x"), chat("y")]
        let openings = ["a": "same", "b": "same", "old": "same", "m1": "merged", "m2": "merged", "x": "apart", "y": "apart"]

        let groups = DuplicateFinder.groups(
            among: chats, vectors: [:], openings: openings,
            mergeGroups: ["m1": "g", "m2": "g"], distinct: [ChatPair("y", "x")], now: now
        )

        #expect(groups.map { $0.chats.map(\.id).sorted() } == [["a", "b"]])
    }

    // MARK: - Open loops

    @Test("A chat is an open loop when it ended on Claude's question or on the user putting it off", arguments: [
        (ChatRole.assistant, "Which option do you want?", Optional(OpenLoopKind.question)),
        (ChatRole.assistant, "Done. All tests pass.", Optional<OpenLoopKind>.none),
        (ChatRole.user, "ok, I'll do this tomorrow", Optional(OpenLoopKind.deferred("ok, I'll do this tomorrow"))),
        (ChatRole.user, "thanks, that works", Optional<OpenLoopKind>.none),
    ])
    func openLoopKinds(role: ChatRole, text: String, expected: OpenLoopKind?) {
        #expect(OpenLoopFinder.kind(of: chat("c", ago: 2 * day, last: (role, text)), now: now) == expected)
    }

    /// Days of quiet, days since the loop was marked done (negative for never), and whether it shows.
    private static let timings: [(quietDays: Double, closedDaysAgo: Double, isOpen: Bool)] = [
        (0.04, -1, false), (2, -1, true), (31, -1, false), (2, 1, false), (2, 3, true),
    ]

    @Test("A loop needs a day of quiet, ends after a month, and stays closed until the chat is active again", arguments: timings)
    func openLoopTiming(timing: (quietDays: Double, closedDaysAgo: Double, isOpen: Bool)) {
        let kind = OpenLoopFinder.kind(
            of: chat("c", ago: timing.quietDays * day, last: (.assistant, "Shall I continue?")),
            closedAt: timing.closedDaysAgo < 0 ? nil : now.addingTimeInterval(-timing.closedDaysAgo * day), now: now
        )

        #expect((kind != nil) == timing.isOpen)
    }

    @Test("A continuation summary or a long message that mentions later is not the user putting work off", arguments: [
        "This session is being continued from a previous conversation that ran out of context. We will fix it later.",
        String(repeating: "A long design note. ", count: 15) + "We can revisit this later.",
    ])
    func notDeferrals(text: String) {
        #expect(OpenLoopFinder.kind(of: chat("c", ago: 2 * day, last: (.user, text)), now: now) == nil)
    }

    @Test("A long deferral is quoted by its first line, shortened")
    func deferralQuote() {
        let text = "Let me think about the pricing page and come back to it later this week\nsecond line"

        let kind = OpenLoopFinder.kind(of: chat("c", ago: 2 * day, last: (.user, text)), now: now)

        #expect(kind == .deferred("Let me think about the pricing page and …"))
    }

    // MARK: - Merging

    @Test("Merged chats are one stack led by the newest, and merging into a stack joins it")
    func merging() throws {
        try add(chat("new", ago: 60))
        try add(chat("mid", ago: 600))
        try add(chat("old", ago: 6000))
        try add(chat("other", ago: 300))
        try library.seedIfNeeded()

        try store.merge(chatIDs: ["old", "mid"])
        try store.merge(chatIDs: ["new", "mid"])
        let stacks = try #require(try library.overview().groups.first).stacks

        #expect(stacks.map(\.id) == ["new", "other"])
        #expect(stacks.first?.merged.map(\.id) == ["mid", "old"])
    }

    @Test("Unmerging takes the whole stack apart")
    func unmerging() throws {
        try add(chat("a", ago: 60))
        try add(chat("b", ago: 600))
        try library.seedIfNeeded()
        try store.merge(chatIDs: ["a", "b"])

        try store.unmerge(stackContaining: "b")

        #expect(try library.overview().groups.first?.stacks.map(\.id) == ["a", "b"])
        #expect(try store.mergeGroups().isEmpty)
    }

    @Test("Search returns merged chats as one result, under the newest chat")
    func searchStacks() throws {
        for (id, ago) in [("new", 60.0), ("old", 6000.0), ("solo", 300.0)] {
            try index.save(chat(id, ago: ago), adding: [ChatTurn(role: .assistant, text: id == "new" ? "nothing relevant" : "pace maths")], fileNumber: 0, offset: 0)
        }
        try store.merge(chatIDs: ["new", "old"])

        let results = try ChatSearch(store: index, embedder: nil, organizer: store).results(for: "pace")

        #expect(Set(results.map(\.id)) == ["new", "solo"])
        #expect(results.first { $0.id == "new" }?.mergedCount == 1)
        #expect(results.first { $0.id == "solo" }?.mergedCount == 0)
    }

    // MARK: - The Inbox as a whole

    @Test("The model lists duplicates and open loops, and each action clears its item", .timeLimit(.minutes(1)))
    @MainActor
    func model() async throws {
        try add(chat("d1", ago: 3600), vector: [1, 0], opening: "same")
        try add(chat("d2", ago: 7200), vector: [1, 0], opening: "same")
        try add(chat("loop", ago: 2 * day, last: (.assistant, "Shall I continue?")), vector: [0, 1])
        let model = WorkstreamsModel(store: store, index: index, clock: { [now] in now })

        await model.refresh(seeding: true)
        let raised = model.inbox
        await model.merge(try #require(raised.duplicates.first).chats)
        await model.close(try #require(raised.openLoops.first))

        #expect(raised.duplicates.map { $0.chats.map(\.id) } == [["d1", "d2"]])
        #expect(raised.openLoops.map(\.id) == ["loop"])
        #expect(raised.openLoops.first?.workstreamName == "api")
        #expect(raised.count == 2)
        #expect(model.inbox.isEmpty)
        #expect(try library.overview().groups.first?.stacks.first { $0.id == "d1" }?.merged.map(\.id) == ["d2"])
    }

    @Test("Not the same keeps a group from being raised again")
    @MainActor
    func markingDistinct() async throws {
        try add(chat("d1"), vector: [1, 0], opening: "same")
        try add(chat("d2"), vector: [1, 0], opening: "same")
        let model = WorkstreamsModel(store: store, index: index, clock: { [now] in now })
        await model.refresh()

        await model.markDistinct(try #require(model.inbox.duplicates.first))

        #expect(model.inbox.duplicates.isEmpty)
    }
}
