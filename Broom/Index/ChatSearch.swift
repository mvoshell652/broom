import Foundation

/// Searches the chat index by the query's words and by its meaning, and merges the two rankings.
public struct ChatSearch: Sendable {
    private let store: ChatIndexStore
    private let embedder: (any SentenceEmbedder)?
    private let organizer: WorkstreamStore?

    /// - Parameter organizer: Where merges are recorded. With it, merged chats come back as one result.
    public init(store: ChatIndexStore, embedder: (any SentenceEmbedder)? = NaturalLanguageEmbedder(), organizer: WorkstreamStore? = nil) {
        self.store = store
        self.embedder = embedder
        self.organizer = organizer
    }

    /// Chats that match `query`, best first.
    ///
    /// A chat ranks by where it falls in each list it appears in (reciprocal rank fusion), so one that matches both the
    /// words and the meaning comes ahead of one that matches either alone. Merged chats are one result, shown as their
    /// newest chat at the rank of whichever of them matched best.
    public func results(for query: String, limit: Int = 20) throws -> [ChatSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let textMatches = try store.textMatches(for: trimmed, limit: Self.candidateCount)
        let snippets = Dictionary(textMatches.map { ($0.chatID, $0.snippet) }, uniquingKeysWith: { first, _ in first })
        var scores: [String: Double] = [:]
        for (rank, match) in textMatches.enumerated() {
            scores[match.chatID, default: 0] += 1 / Double(Self.fusionConstant + rank)
        }
        for (rank, id) in try meaningMatches(for: trimmed).enumerated() {
            scores[id, default: 0] += 1 / Double(Self.fusionConstant + rank)
        }

        let ranked = scores.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        let mergeGroups = try organizer?.mergeGroups() ?? [:]
        let archived = try organizer?.archivedChats() ?? [:]
        var members: [String: [String]] = [:]
        for (id, group) in mergeGroups { members[group, default: []].append(id) }

        var results: [ChatSearchResult] = []
        var shownGroups: Set<String> = []
        for id in ranked where results.count < limit {
            guard let group = mergeGroups[id] else {
                if let chat = try store.chat(id: id) {
                    results.append(ChatSearchResult(
                        chat: chat, snippet: snippets[id] ?? nil, isArchived: WorkstreamLibrary.isArchived(chat, in: archived)
                    ))
                }
                continue
            }
            guard shownGroups.insert(group).inserted else { continue }
            let chats = try (members[group] ?? []).compactMap { try store.chat(id: $0) }
            guard let newest = chats.max(by: { ($0.lastActivityAt ?? .distantPast, $1.id) < ($1.lastActivityAt ?? .distantPast, $0.id) }) else { continue }
            results.append(ChatSearchResult(
                chat: newest, snippet: snippets[id] ?? nil, mergedCount: chats.count - 1,
                isArchived: WorkstreamLibrary.isArchived(newest, in: archived)
            ))
        }
        return results
    }

    /// The chats closest in meaning to `query`, closest first, leaving out those too far to be related.
    private func meaningMatches(for query: String) throws -> [String] {
        guard let embedder, let queryVector = embedder.vector(for: query) else { return [] }
        return try store.embeddings()
            .map { (id: $0.key, similarity: VectorMath.cosineSimilarity(queryVector, $0.value)) }
            .filter { $0.similarity >= Self.minimumSimilarity }
            .sorted { ($0.similarity, $1.id) > ($1.similarity, $0.id) }
            .prefix(Self.candidateCount)
            .map(\.id)
    }

    private static let candidateCount = 50
    private static let fusionConstant = 60
    /// Below this the sentence embedding does not tell related text from unrelated: unrelated pairs measured 0.25 to 0.35.
    private static let minimumSimilarity: Float = 0.45
}
