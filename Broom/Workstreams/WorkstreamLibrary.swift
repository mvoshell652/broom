import Foundation

/// Sorts the indexed chats into the user's workstreams, and works out what the Inbox should raise.
///
/// A chat belongs to the workstream it was filed in by hand, or else the one that owns its project folder. Merged
/// chats are one stack, which goes where its newest chat goes. Archived chats are left out until they are active again.
///
/// Changes made through it are recorded, so each can be undone for 30 days.
public struct WorkstreamLibrary: Sendable {
    private let store: WorkstreamStore
    private let index: ChatIndexStore

    public init(store: WorkstreamStore, index: ChatIndexStore) {
        self.store = store
        self.index = index
    }

    /// Makes a workstream for every project folder in the index, once. Call after a full pass over the transcripts,
    /// so every folder is known.
    @discardableResult
    public func seedIfNeeded() throws -> Bool {
        guard try !store.isSeeded() else { return false }
        let folders = Set(try index.allChats().compactMap { $0.cwd.map(ProjectFolder.root(of:)) })
        guard !folders.isEmpty else { return false }
        return try store.seed(folders: Array(folders))
    }

    /// Makes a workstream for each project folder that has none yet, named after the folder. Does nothing before the
    /// first seeding. Not recorded: the user did not do it, and there is nothing to choose.
    public func addNewFolders() throws {
        guard try store.isSeeded() else { return }
        let owned = try store.folderOwners()
        let folders = Set(try index.allChats().compactMap { $0.cwd.map(ProjectFolder.root(of:)) })
        for folder in folders.subtracting(owned.keys).sorted() {
            _ = try store.create(name: ProjectFolder.name(of: folder), folders: [folder])
        }
    }

    /// Every chat in its workstream, and those that have none.
    public func overview() throws -> WorkstreamOverview {
        let folderOwners = try store.folderOwners()
        let filedChats = try store.filedChats()
        var stacksByWorkstream: [Int64: [ChatStack]] = [:]
        var unsorted: [ChatStack] = []
        let archived = try store.archivedChats()
        // The stacks come most recently active first, and both lists keep that order.
        for stack in Self.stacks(of: try index.allChats(), mergeGroups: try store.mergeGroups()) {
            let chat = stack.chat
            if Self.isArchived(chat, in: archived) { continue }
            if let workstream = filedChats[chat.id] ?? chat.cwd.flatMap({ folderOwners[ProjectFolder.root(of: $0)] }) {
                stacksByWorkstream[workstream, default: []].append(stack)
            } else {
                unsorted.append(stack)
            }
        }
        let groups = try store.workstreams()
            .map { WorkstreamGroup(workstream: $0, stacks: stacksByWorkstream[$0.id] ?? []) }
            .sorted { ($0.lastActivityAt ?? .distantPast, $1.id) > ($1.lastActivityAt ?? .distantPast, $0.id) }
        return WorkstreamOverview(groups: groups, unsorted: unsorted)
    }

    /// What the Inbox lists for `overview` as of `now`.
    public func inbox(for overview: WorkstreamOverview, now: Date) throws -> InboxContents {
        let workstreams = Dictionary(overview.groups.map { ($0.id, $0.workstream) }, uniquingKeysWith: { first, _ in first })
        let filed = Self.workstreamIDs(in: overview)
        let closed = try store.closedLoops()
        let stacks = overview.groups.flatMap(\.stacks) + overview.unsorted
        let openLoops = stacks
            .compactMap { stack -> OpenLoop? in
                let chat = stack.chat
                guard let kind = OpenLoopFinder.kind(of: chat, closedAt: closed[chat.id], now: now) else { return nil }
                return OpenLoop(chat: chat, kind: kind, workstreamName: filed[chat.id].flatMap { workstreams[$0]?.name })
            }
            .sorted { ($0.chat.lastActivityAt ?? .distantPast, $0.id) > ($1.chat.lastActivityAt ?? .distantPast, $1.id) }

        let chats = stacks.flatMap(\.all)
        let duplicates = DuplicateFinder.groups(
            among: chats, vectors: try index.embeddings(), openings: try index.embeddingSources(forChats: chats.map(\.id)),
            mergeGroups: try store.mergeGroups(), distinct: try store.distinctPairs(), now: now
        )
        return InboxContents(duplicates: duplicates, openLoops: openLoops)
    }

    /// The weekly sweep's cards for `overview` and its `inbox` as of `now`: merges, then archiving and open loops, leaving out cards skipped within the last week.
    public func sweepCards(for overview: WorkstreamOverview, inbox: InboxContents, now: Date) throws -> [SweepCard] {
        let closed = try store.closedLoops()
        let archives = overview.groups.compactMap { group -> SweepCard? in
            let chats = group.stacks
                .filter { stack in
                    guard let lastActivityAt = stack.chat.lastActivityAt, now.timeIntervalSince(lastActivityAt) >= Self.archiveAge else { return false }
                    // A chat left open is not resolved, unless its loop was marked done.
                    return OpenLoopFinder.ending(of: stack.chat) == nil || closed[stack.chat.id] != nil
                }
                .flatMap(\.all)
            return chats.isEmpty ? nil : .archive(workstream: group.workstream, chats: chats)
        }
        let cards = inbox.duplicates.map(SweepCard.merge)
            + archives
            + inbox.openLoops.map(SweepCard.revisit)
        let skipped = try store.skippedCards(at: now)
        return cards.filter { !skipped.contains($0.id) }
    }

    /// Reads everything the tabs show as of `now`.
    public func snapshot(now: Date) throws -> OrganizerSnapshot {
        var snapshot = OrganizerSnapshot()
        snapshot.overview = try overview()
        snapshot.inbox = try inbox(for: snapshot.overview, now: now)
        snapshot.sweepCards = try sweepCards(for: snapshot.overview, inbox: snapshot.inbox, now: now)
        snapshot.history = try history(now: now)
        snapshot.lastSweptAt = try store.lastSweptAt()
        return snapshot
    }

    /// Records that a sweep was finished.
    public func finishSweep(at date: Date) throws {
        try store.setLastSwept(at: date)
    }

    // MARK: - Changes

    /// Merges chats into one stack.
    public func merge(_ chats: [IndexedChat], at date: Date) throws {
        guard chats.count > 1 else { return }
        let previous = try store.merge(chatIDs: chats.map(\.id))
        try record(.merged(previousGroups: previous), "Merged \(chats.count) chats: \(Self.quoted(chats[0].title))", at: date)
    }

    /// Records that these chats are not duplicates of each other.
    public func markDistinct(_ chats: [IndexedChat], at date: Date) throws {
        guard chats.count > 1 else { return }
        try store.markDistinct(chatIDs: chats.map(\.id))
        try record(.markedDistinct(chatIDs: chats.map(\.id)), "Kept apart: \(Self.quoted(chats[0].title))", at: date)
    }

    /// Archives a workstream's chats. They leave the lists until they are active again; search still finds them.
    public func archive(_ chats: [IndexedChat], in workstream: Workstream, at date: Date) throws {
        guard !chats.isEmpty else { return }
        try store.archive(chatIDs: chats.map(\.id), at: date)
        let count = chats.count == 1 ? "1 chat" : "\(chats.count) chats"
        try record(.archived(chatIDs: chats.map(\.id)), "Archived \(count) in \(workstream.name)", at: date)
    }

    /// Marks an open loop done. It comes back if the chat is active again.
    public func close(_ loop: OpenLoop, at date: Date) throws {
        let previous = try store.closedLoops()[loop.id]
        try store.closeLoop(chatID: loop.id, at: date)
        try record(
            .closedLoop(chatID: loop.id, previouslyClosedAt: previous?.timeIntervalSinceReferenceDate),
            "Marked \(Self.quoted(loop.chat.title)) done", at: date
        )
    }

    /// The changes of the last 30 days that can still be undone, newest first.
    public func recentChanges(now: Date) throws -> [OrganizerLogEntry] {
        try store.log(since: now.addingTimeInterval(-Self.undoWindow))
    }

    /// The changes of the last 30 days as History shows them, newest first.
    public func history(now: Date) throws -> [HistoryItem] {
        let entries = try recentChanges(now: now)
        guard !entries.isEmpty else { return [] }
        let chatsByID = Dictionary(try index.allChats().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.map { HistoryItem(entry: $0, chatsByID: chatsByID) }
    }

    /// Puts back what a recorded change did.
    public func undo(_ entry: OrganizerLogEntry) throws {
        switch entry.change {
        case .merged(let previousGroups): try store.restoreMergeGroups(previousGroups)
        case .markedDistinct(let chatIDs): try store.unmarkDistinct(chatIDs: chatIDs)
        case .filed(let chatID, let previous):
            if let previous {
                try store.file(chatID: chatID, in: previous)
            } else {
                try store.unfile(chatID: chatID)
            }
        case .createdWorkstream(let id): try store.deleteWorkstream(id)
        case .archived(let chatIDs): try store.unarchive(chatIDs: chatIDs)
        case .closedLoop(let chatID, let previouslyClosedAt):
            try store.reopenLoop(chatID: chatID, previouslyClosedAt: previouslyClosedAt.map(Date.init(timeIntervalSinceReferenceDate:)))
        }
        try store.removeLogEntry(entry.id)
    }

    /// Keeps a card out of the sweep for a week.
    public func skip(_ card: SweepCard, at date: Date) throws {
        try store.skipCard(id: card.id, until: date.addingTimeInterval(Self.skipDuration))
    }

    private func record(_ change: OrganizerChange, _ summary: String, at date: Date) throws {
        try store.record(change, summary: summary, at: date, forgettingBefore: date.addingTimeInterval(-Self.undoWindow))
    }

    private static func quoted(_ title: String) -> String {
        "“\(title.isEmpty ? "Untitled chat" : title)”"
    }

    /// Whether `chat` was archived and has not been active since.
    static func isArchived(_ chat: IndexedChat, in archived: [String: Date]) -> Bool {
        archived[chat.id].map { $0 >= chat.lastActivityAt ?? .distantPast } ?? false
    }

    /// How long a chat must be quiet before the sweep offers to archive it.
    static let archiveAge: TimeInterval = 90 * 24 * 3600
    /// How long a change can be undone for.
    static let undoWindow: TimeInterval = 30 * 24 * 3600
    /// How long a skipped card stays out of the sweep.
    static let skipDuration: TimeInterval = 7 * 24 * 3600

    /// Groups `chats` (most recently active first) into stacks, each led by its newest chat, in the same order.
    static func stacks(of chats: [IndexedChat], mergeGroups: [String: String]) -> [ChatStack] {
        var stacks: [ChatStack] = []
        var position: [String: Int] = [:]
        for chat in chats {
            if let group = mergeGroups[chat.id] {
                if let index = position[group] {
                    stacks[index].merged.append(chat)
                    continue
                }
                position[group] = stacks.count
            }
            stacks.append(ChatStack(chat: chat))
        }
        return stacks
    }

    /// The workstream of every filed chat in `overview`, by chat id.
    private static func workstreamIDs(in overview: WorkstreamOverview) -> [String: Int64] {
        var filed: [String: Int64] = [:]
        for group in overview.groups {
            for chat in group.chats { filed[chat.id] = group.id }
        }
        return filed
    }
}
