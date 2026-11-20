import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("Sweep")
struct SweepTests {
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

    @discardableResult
    private func add(
        _ id: String, cwd: String? = "/code/api", daysAgo: Double = 1, last: (ChatRole, String)? = nil, opening: String? = nil
    ) throws -> IndexedChat {
        let date = now.addingTimeInterval(-daysAgo * day)
        let chat = IndexedChat(
            id: id, title: id, cwd: cwd, lastTurnText: last?.1, lastTurnRole: last?.0,
            startedAt: date.addingTimeInterval(-60), lastActivityAt: date, transcriptPath: "/tmp/\(id)"
        )
        try index.save(chat, adding: [ChatTurn(role: .assistant, text: "words about \(id)")], fileNumber: 0, offset: 0)
        if let opening { try index.saveEmbedding([1, 0], of: opening, forChat: id) }
        return chat
    }

    private func cards(at date: Date? = nil) throws -> [SweepCard] {
        try library.snapshot(now: date ?? now).sweepCards
    }

    // MARK: - The deck

    @Test("The sweep offers merges, then archiving and open loops")
    func cardOrder() throws {
        try add("old", daysAgo: 120)
        try library.seedIfNeeded()
        try add("d1", daysAgo: 2, opening: "same")
        try add("d2", daysAgo: 3, opening: "same")
        try add("loop", daysAgo: 5, last: (.assistant, "Shall I continue?"))

        let cards = try cards()

        #expect(cards.map(\.kind) == [.merge, .archive, .revisit])
        #expect(cards.map(\.id) == ["merge:d1+d2", "archive:1", "revisit:loop"])
    }

    @Test("Archiving is offered for chats quiet for 90 days that were not left open, or whose loop was marked done")
    func archiveCandidates() throws {
        try add("fresh", daysAgo: 30)
        try add("resolved", daysAgo: 100, last: (.assistant, "All done."))
        try add("open", daysAgo: 110, last: (.assistant, "Which one?"))
        try add("closed", daysAgo: 120, last: (.assistant, "Which one?"))
        try library.seedIfNeeded()
        try store.closeLoop(chatID: "closed", at: now)

        guard case .archive(let workstream, let chats)? = try cards().first(where: { $0.kind == .archive }) else {
            Issue.record("No archive card")
            return
        }

        #expect(workstream.name == "api")
        #expect(chats.map(\.id) == ["resolved", "closed"])
    }

    @Test("A skipped card stays out of the sweep for a week")
    func skipping() throws {
        try add("old", daysAgo: 120)
        try library.seedIfNeeded()
        let card = try #require(try cards().first)

        try library.skip(card, at: now)

        #expect(try cards().isEmpty)
        #expect(try cards(at: now.addingTimeInterval(6 * day)).isEmpty)
        #expect(try cards(at: now.addingTimeInterval(8 * day)).map(\.id) == [card.id])
    }

    // MARK: - Archiving

    @Test("Archived chats leave the lists, stay in search marked archived, and return when active again")
    func archiving() throws {
        let old = try add("old", daysAgo: 120)
        try add("recent", daysAgo: 1)
        try library.seedIfNeeded()
        let api = try #require(try store.workstreams().first)

        try library.archive([old], in: api, at: now)
        let listed = try library.overview().groups.first?.chats.map(\.id)
        let found = try ChatSearch(store: index, embedder: nil, organizer: store).results(for: "old")
        try add("old", daysAgo: -1)

        #expect(listed == ["recent"])
        #expect(found.map(\.id) == ["old"])
        #expect(found.first?.isArchived == true)
        #expect(try library.overview().groups.first?.chats.map(\.id) == ["old", "recent"])
    }

    // MARK: - Undo

    @Test("Undoing a merge puts every chat back in the stack it was in before")
    func undoMerge() throws {
        let a = try add("a", daysAgo: 1), b = try add("b", daysAgo: 2), c = try add("c", daysAgo: 3)
        try library.seedIfNeeded()
        try store.merge(chatIDs: ["b", "c"])
        let before = try store.mergeGroups()

        try library.merge([a, b], at: now)
        let merged = try library.overview().groups.first?.stacks.map { $0.all.map(\.id) }
        try library.undo(try #require(try library.recentChanges(now: now).first))

        #expect(merged == [["a", "b", "c"]])
        #expect(try store.mergeGroups() == before)
        #expect(try library.recentChanges(now: now).isEmpty)
        _ = c
    }

    @Test("Undoing puts back an archive, a closed loop and a not-the-same mark")
    func undoOthers() throws {
        let api1 = try add("api1")
        try library.seedIfNeeded()
        let loop = OpenLoop(chat: try add("loop", daysAgo: 3, last: (.assistant, "Shall I continue?")), kind: .question)
        let api = try #require(try store.workstreams().first)

        try library.archive([api1], in: api, at: now)
        try library.close(loop, at: now)
        try library.markDistinct([api1, loop.chat], at: now)
        let changes = try library.recentChanges(now: now)
        for entry in changes { try library.undo(entry) }

        #expect(changes.map(\.summary) == [
            "Kept apart: “api1”", "Marked “loop” done", "Archived 1 chat in api",
        ])
        #expect(try store.filedChats().isEmpty)
        #expect(try store.workstreams().map(\.name) == ["api"])
        #expect(try store.archivedChats().isEmpty)
        #expect(try store.closedLoops().isEmpty)
        #expect(try store.distinctPairs().isEmpty)
    }

    @Test("Changes can be undone for 30 days, and older ones are forgotten")
    func undoWindow() throws {
        let a = try add("a"), b = try add("b")

        try library.markDistinct([a, b], at: now.addingTimeInterval(-31 * day))
        let afterAMonth = try library.recentChanges(now: now)
        try library.markDistinct([a, b], at: now)

        #expect(afterAMonth.isEmpty)
        #expect(try library.recentChanges(now: now.addingTimeInterval(29 * day)).count == 1)
        #expect(try store.log(since: .distantPast).count == 1)
    }

    // MARK: - The model

    @Test("A sweep goes card by card, passes over cards dealt with elsewhere, and records when it finished", .timeLimit(.minutes(1)))
    @MainActor
    func deck() async throws {
        try add("old", daysAgo: 120)
        try add("d1", daysAgo: 2, opening: "same")
        try add("d2", daysAgo: 3, opening: "same")
        try add("loop", daysAgo: 5, last: (.assistant, "Shall I continue?"))
        let model = WorkstreamsModel(store: store, index: index, clock: { [now] in now })
        await model.refresh(seeding: true)

        model.startSweep()
        let dealt = model.deck?.cards.map(\.kind)
        // The merge is accepted from the deck, the archive is skipped, and the loop is closed from the Inbox meanwhile.
        if case .merge(let group)? = model.deck?.current { await model.merge(group.chats) }
        await model.advance()
        let second = model.deck?.current?.kind
        await model.close(try #require(model.inbox.openLoops.first))
        await model.skipCurrentCard()

        #expect(dealt == [.merge, .archive, .revisit])
        #expect(second == .archive)
        #expect(model.deck == nil)
        #expect(model.lastSweptAt == now)
        #expect(model.sweepCards.isEmpty)
        #expect(model.history.map(\.headline) == ["Marked “loop” done", "Merged 2 chats in api"])
    }

    @Test("A recorded change is offered for undo where it was made, and undoing it takes the offer down")
    @MainActor
    func changeToast() async throws {
        try add("d1", daysAgo: 2, opening: "same")
        try add("d2", daysAgo: 3, opening: "same")
        let model = WorkstreamsModel(store: store, index: index, clock: { [now] in now })
        await model.refresh(seeding: true)

        await model.merge(try #require(model.inbox.duplicates.first).chats)
        let offered = model.lastChange
        await model.undo(try #require(offered))

        #expect(offered?.summary == "Merged 2 chats: “d1”")
        #expect(model.lastChange == nil)
        #expect(model.history.isEmpty)
        #expect(model.inbox.duplicates.count == 1)
    }

    @Test("Ending a sweep early leaves its cards waiting and records no sweep")
    @MainActor
    func endingEarly() async throws {
        try add("old", daysAgo: 120)
        let model = WorkstreamsModel(store: store, index: index, clock: { [now] in now })
        await model.refresh(seeding: true)

        model.startSweep()
        model.endSweep()

        #expect(model.deck == nil)
        #expect(model.sweepCards.count == 1)
        #expect(model.lastSweptAt == nil)
    }
}
