import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("Workstreams")
struct WorkstreamTests {
    private let store: WorkstreamStore
    private let index: ChatIndexStore
    private let library: WorkstreamLibrary
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        store = try WorkstreamStore()
        index = try ChatIndexStore()
        library = WorkstreamLibrary(store: store, index: index)
    }

    /// Adds a chat to the index, last active `ago` seconds before `now`.
    private func addChat(_ id: String, cwd: String?, ago: TimeInterval = 60, vector: [Float]? = nil) throws {
        let chat = IndexedChat(id: id, title: id, cwd: cwd, lastActivityAt: now.addingTimeInterval(-ago), transcriptPath: "/tmp/\(id)")
        try index.save(chat, adding: [], fileNumber: 0, offset: 0)
        if let vector { try index.saveEmbedding(vector, of: id, forChat: id) }
    }

    // MARK: - Project folders

    @Test("A worktree belongs to the repository it was made from", arguments: [
        ("/code/api", "/code/api"),
        ("/code/api/.claude/worktrees/fix-login", "/code/api"),
        ("/code/api/.claude/worktrees/fix-login/packages/core", "/code/api"),
        ("/code/worktrees/notes", "/code/worktrees/notes"),
    ])
    func projectRoot(cwd: String, root: String) {
        #expect(ProjectFolder.root(of: cwd) == root)
    }

    // MARK: - Seeding

    @Test("Seeding makes one workstream per project folder, named after it, and only once")
    func seeding() throws {
        try addChat("a1", cwd: "/code/api")
        try addChat("a2", cwd: "/code/api/.claude/worktrees/fix-login")
        try addChat("w1", cwd: "/code/web")

        let didSeed = try library.seedIfNeeded()
        try addChat("n1", cwd: "/code/notes")
        let didSeedAgain = try library.seedIfNeeded()

        #expect(didSeed)
        #expect(!didSeedAgain)
        #expect(try store.workstreams().map(\.name) == ["api", "web"])
        #expect(try store.folderOwners().keys.sorted() == ["/code/api", "/code/web"])
    }

    @Test("An empty index does not use up the one seeding")
    func seedingWaitsForChats() throws {
        let didSeed = try library.seedIfNeeded()
        try addChat("a1", cwd: "/code/api")
        let didSeedLater = try library.seedIfNeeded()

        #expect(!didSeed)
        #expect(didSeedLater)
    }

    // MARK: - Sorting chats

    @Test("Chats are grouped by their folder's workstream, the most recently active workstream and chat first")
    func overviewGroups() throws {
        try addChat("a-old", cwd: "/code/api", ago: 900)
        try addChat("a-tree", cwd: "/code/api/.claude/worktrees/fix-login", ago: 300)
        try addChat("w1", cwd: "/code/web", ago: 30)
        try library.seedIfNeeded()

        let overview = try library.overview()

        #expect(overview.groups.map(\.workstream.name) == ["web", "api"])
        #expect(overview.groups[1].chats.map(\.id) == ["a-tree", "a-old"])
        #expect(overview.groups[1].lastActivityAt == now.addingTimeInterval(-300))
        #expect(overview.unsorted.isEmpty)
    }

    @Test("After seeding, a new chat in a known folder is filed and one in a new folder is unsorted")
    func newChats() throws {
        try addChat("a1", cwd: "/code/api")
        try library.seedIfNeeded()
        try addChat("a2", cwd: "/code/api", ago: 10)
        try addChat("n1", cwd: "/code/notes", ago: 20)
        try addChat("none", cwd: nil, ago: 5)

        let overview = try library.overview()

        #expect(overview.groups.map { $0.chats.map(\.id) } == [["a2", "a1"]])
        #expect(overview.unsorted.map(\.id) == ["none", "n1"])
    }

    @Test("Filing a chat by hand wins over its folder")
    func filingByHand() throws {
        try addChat("a1", cwd: "/code/api")
        try addChat("w1", cwd: "/code/web")
        try library.seedIfNeeded()
        let web = try #require(try store.workstreams().first { $0.name == "web" })

        try store.file(chatID: "a1", in: web.id)
        let overview = try library.overview()

        #expect(overview.groups.first { $0.id == web.id }?.chats.map(\.id).sorted() == ["a1", "w1"])
        #expect(overview.groups.first { $0.id != web.id }?.chats.isEmpty == true)
    }

    @Test("A workstream with no chats is listed last")
    func emptyWorkstreamLast() throws {
        try store.create(name: "Empty")
        try store.create(name: "Busy", folders: ["/code/api"])
        try addChat("a1", cwd: "/code/api")

        #expect(try library.overview().groups.map(\.workstream.name) == ["Busy", "Empty"])
    }

    // MARK: - Renaming

    @Test("Renaming trims the name, and a blank name changes nothing", arguments: [("  Acme backend ", "Acme backend"), ("   ", "api")])
    func renaming(typed: String, expected: String) throws {
        let workstream = try store.create(name: "api")

        try store.rename(workstream.id, to: typed)

        #expect(try store.workstreams().map(\.name) == [expected])
    }

    // MARK: - New folders

    @Test("After seeding, each new project folder gets a workstream of its own, once")
    func newFolders() throws {
        try addChat("a1", cwd: "/code/api")
        try library.addNewFolders()
        let beforeSeeding = try store.workstreams()
        try library.seedIfNeeded()
        try addChat("n1", cwd: "/code/notes")
        try addChat("n2", cwd: "/code/notes/sub")
        try addChat("none", cwd: nil)

        try library.addNewFolders()
        try library.addNewFolders()
        let overview = try library.overview()

        #expect(beforeSeeding.isEmpty)
        #expect(try store.workstreams().map(\.name).sorted() == ["api", "notes", "sub"])
        #expect(overview.unsorted.map(\.id) == ["none"])
    }
}
