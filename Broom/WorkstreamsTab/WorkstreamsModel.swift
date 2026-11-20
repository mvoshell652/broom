import BroomCore
import Foundation
import Observation
import SwiftUI
import os

/// How the user's chats are organised, kept current as the index changes: what the Inbox raises, the weekly sweep, and
/// the History of changes.
@MainActor
@Observable
final class WorkstreamsModel {
    /// Chats to merge and to finish.
    private(set) var inbox = InboxContents()
    /// The sweep's cards that are waiting.
    private(set) var sweepCards: [SweepCard] = []
    /// Changes from the last 30 days that can be undone, newest first.
    private(set) var history: [HistoryItem] = []
    private(set) var lastSweptAt: Date?
    /// The change just made, while its toast still offers to undo it.
    private(set) var lastChange: OrganizerLogEntry?
    /// The sweep in progress, if one was started and not yet finished.
    private(set) var deck: SweepDeck?

    private let library: WorkstreamLibrary?
    private let clock: @MainActor () -> Date
    private let log = Logger(subsystem: "app.broom", category: "workstreams")
    private var toastTask: Task<Void, Never>?

    /// How long a change's toast, with its Undo, stays up.
    static let toastDuration: Duration = .seconds(5)

    /// Without a store or an index, as in previews, the model stays empty.
    init(store: WorkstreamStore?, index: ChatIndexStore?, clock: @escaping @MainActor () -> Date = { Date() }) {
        self.clock = clock
        if let store, let index {
            library = WorkstreamLibrary(store: store, index: index)
        } else {
            library = nil
        }
    }

    /// Reads the Inbox, the sweep and History again.
    ///
    /// - Parameter seeding: Whether to make workstreams for project folders that have none first. Pass `true` only
    ///   after a full pass over the transcripts.
    func refresh(seeding: Bool = false) async {
        guard let library else { return }
        do {
            let snapshot = try await Self.read(from: library, seeding: seeding, now: clock())
            if inbox != snapshot.inbox { inbox = snapshot.inbox }
            if sweepCards != snapshot.sweepCards { sweepCards = snapshot.sweepCards }
            if history != snapshot.history { history = snapshot.history }
            if lastSweptAt != snapshot.lastSweptAt { lastSweptAt = snapshot.lastSweptAt }
        } catch {
            log.error("Could not read the workstreams: \(error)")
        }
    }

    // MARK: - Changes

    /// Merges chats that look like duplicates into one stack.
    func merge(_ chats: [IndexedChat]) async {
        await change { library, date in try library.merge(chats, at: date) }
    }

    /// Records that a group's chats are not duplicates, so they are not raised together again.
    func markDistinct(_ group: DuplicateGroup) async {
        await change { library, date in try library.markDistinct(group.chats, at: date) }
    }

    /// Archives a workstream's chats.
    func archive(_ chats: [IndexedChat], in workstream: Workstream) async {
        await change { library, date in try library.archive(chats, in: workstream, at: date) }
    }

    /// Marks an open loop done. It comes back if the chat is active again.
    func close(_ loop: OpenLoop) async {
        await change { library, date in try library.close(loop, at: date) }
    }

    /// Puts back what a recent change did.
    func undo(_ entry: OrganizerLogEntry) async {
        if lastChange?.id == entry.id { lastChange = nil }
        await change { library, _ in try library.undo(entry) }
    }

    /// Takes the toast down, for when the popover closes.
    func dismissToast() {
        toastTask?.cancel()
        lastChange = nil
    }

    // MARK: - The sweep

    /// Begins a sweep through the waiting cards. Does nothing if one is in progress or nothing is waiting.
    func startSweep() {
        guard deck == nil, !sweepCards.isEmpty else { return }
        deck = SweepDeck(cards: sweepCards)
    }

    /// Puts the deck away without finishing it. The cards not yet reached stay in the Inbox.
    func endSweep() {
        deck = nil
    }

    /// Leaves the top card for next week and moves on.
    func skipCurrentCard() async {
        guard let card = deck?.current else { return }
        await change { library, date in try library.skip(card, at: date) }
        await advance()
    }

    /// Moves past the top card after the user has acted on it.
    func advance() async {
        guard var deck else { return }
        let waiting = Set(sweepCards.map(\.id))
        // Cards dealt with elsewhere since the sweep began, in the Inbox for one, are passed over.
        repeat { deck.position += 1 } while deck.current.map { !waiting.contains($0.id) } ?? false
        if deck.current == nil {
            self.deck = nil
            await change { library, date in try library.finishSweep(at: date) }
        } else {
            self.deck = deck
        }
    }

    /// Makes one change off the main actor, then reads everything again.
    private func change(_ work: @escaping @Sendable (WorkstreamLibrary, Date) throws -> Void) async {
        guard let library else { return }
        let newestBefore = history.first?.id ?? 0
        do {
            try await Self.perform(work, library: library, date: clock())
        } catch {
            log.error("Could not save the change: \(error)")
        }
        await refresh()
        // A change that was recorded gets a toast with Undo, wherever it was made.
        if let newest = history.first, newest.id > newestBefore { announce(newest.entry) }
    }

    private func announce(_ entry: OrganizerLogEntry) {
        lastChange = entry
        // The toast is visual only, so say it for VoiceOver too.
        AccessibilityNotification.Announcement(entry.summary).post()
        toastTask?.cancel()
        toastTask = Task {
            do { try await Task.sleep(for: Self.toastDuration) } catch { return }
            lastChange = nil
        }
    }

    @concurrent
    private nonisolated static func perform(
        _ work: @Sendable (WorkstreamLibrary, Date) throws -> Void, library: WorkstreamLibrary, date: Date
    ) async throws {
        try work(library, date)
    }

    /// Off the main actor: it reads every chat in the index and compares the recent ones with each other.
    @concurrent
    private nonisolated static func read(from library: WorkstreamLibrary, seeding: Bool, now: Date) async throws -> OrganizerSnapshot {
        if seeding {
            try library.seedIfNeeded()
            try library.addNewFolders()
        }
        return try library.snapshot(now: now)
    }
}
