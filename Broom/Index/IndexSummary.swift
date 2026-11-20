/// What one pass of the indexer did.
public struct IndexSummary: Equatable, Sendable {
    /// Transcript files that had something new.
    public var filesRead = 0
    /// Prompts and replies added to the index.
    public var turnsAdded = 0
    /// Chats whose comparison vector was computed.
    public var chatsEmbedded = 0
    /// Transcripts that were replaced or cut short, whose chats were indexed again from the start.
    public var filesReset = 0

    /// Whether the pass changed anything in the index.
    public var hasChanges: Bool { turnsAdded > 0 || chatsEmbedded > 0 || filesReset > 0 }

    public init() {}
}
