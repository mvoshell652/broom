import BroomCore
import Foundation
import Observation
import os

/// The search window's state, and the indexer that keeps the chat index current while the app runs.
@MainActor
@Observable
final class SearchModel {
    /// What is typed in the search field.
    var query = ""
    /// The chats found for `query`, best first.
    private(set) var results: [ChatSearchResult] = []
    /// The result the arrow keys are on.
    var selectedID: String?
    /// How many chats are in the index.
    private(set) var indexedCount = 0
    /// Whether a pass over the transcripts is running.
    private(set) var isIndexing = false
    /// Whether a pass over the transcripts has finished since launch.
    @ObservationIgnored private var hasFinishedPass = false
    /// Goes up each time the window is shown, so the field can take the keyboard again.
    private(set) var presentationCount = 0

    private let store: ChatIndexStore?
    private let indexer: ChatIndexer?
    private let search: ChatSearch?
    private let log = Logger(subsystem: "app.broom", category: "search")

    /// Called after each pass over the transcripts that finished.
    var didIndex: (() async -> Void)?

    /// How long the indexer waits between passes.
    static let indexInterval: Duration = .seconds(60)

    /// - Parameter projectsDirectory: Where transcripts are read from. `nil` leaves the index as it is, for previews and tests.
    /// - Parameter organizer: Where merges are recorded, so merged chats are found as one result.
    init(store: ChatIndexStore?, projectsDirectory: URL?, embedder: (any SentenceEmbedder)? = NaturalLanguageEmbedder(), organizer: WorkstreamStore? = nil) {
        self.store = store
        search = store.map { ChatSearch(store: $0, embedder: embedder, organizer: organizer) }
        if let store, let projectsDirectory {
            indexer = ChatIndexer(projectsDirectory: projectsDirectory, store: store, embedder: embedder)
        } else {
            indexer = nil
        }
        refreshCount()
    }

    /// The selected result.
    var selected: ChatSearchResult? {
        results.first { $0.id == selectedID }
    }

    /// Indexes what is new, then again every minute, until the calling task is cancelled.
    func runIndexing() async {
        guard let indexer else { return }
        while !Task.isCancelled {
            isIndexing = true
            var didChange = false
            do {
                let summary = try await indexer.indexAll()
                // The first pass always counts: it is when the folders are first seeded.
                didChange = summary.hasChanges || !hasFinishedPass
                hasFinishedPass = true
                if summary.turnsAdded > 0 {
                    log.notice("Indexed \(summary.turnsAdded, privacy: .public) turns from \(summary.filesRead, privacy: .public) files")
                }
            } catch is CancellationError {
                break
            } catch {
                log.error("Indexing failed: \(error)")
            }
            isIndexing = false
            // A quiet minute reads nothing and redraws nothing.
            if didChange {
                refreshCount()
                await didIndex?()
            }
            do { try await Task.sleep(for: Self.indexInterval) } catch { break }
        }
        isIndexing = false
    }

    /// Runs the search for the current query. Call when the query changes; a newer call replaces an older one's results.
    func updateResults() async {
        guard let search else { return }
        let query = query
        // Wait out fast typing, so each keystroke does not start a search.
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        let found = await Self.find(query, with: search)
        guard !Task.isCancelled, query == self.query else { return }
        results = found
        if selected == nil { selectedID = found.first?.id }
    }

    /// Moves the selection `offset` results, stopping at either end.
    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : results.count)
        selectedID = results[min(max(index + offset, 0), results.count - 1)].id
    }

    /// Records that the window is being shown, starting from an empty field.
    func willPresent() {
        query = ""
        results = []
        selectedID = nil
        refreshCount()
        presentationCount += 1
    }

    /// Deletes the index. The next indexing pass rebuilds it from the transcripts.
    func deleteIndex() async {
        guard let store else { return }
        do {
            try await Self.removeAll(from: store)
        } catch {
            log.error("Could not delete the index: \(error)")
        }
        results = []
        refreshCount()
    }

    /// Off the main actor: emptying a large index takes long enough to stall the window that asked for it.
    @concurrent
    private nonisolated static func removeAll(from store: ChatIndexStore) async throws {
        try store.removeAll()
    }

    private func refreshCount() {
        indexedCount = (try? store?.chatCount()) ?? 0
    }

    /// The search itself, off the main actor: it reads the database and compares vectors.
    @concurrent
    private nonisolated static func find(_ query: String, with search: ChatSearch) async -> [ChatSearchResult] {
        (try? search.results(for: query)) ?? []
    }
}
