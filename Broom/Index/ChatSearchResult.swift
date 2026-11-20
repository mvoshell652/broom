/// One chat found by a search, with the passage that matched.
public struct ChatSearchResult: Identifiable, Equatable, Sendable {
    public var chat: IndexedChat
    /// A passage from the chat containing the query's words, or `nil` when it matched by meaning alone.
    public var snippet: String?
    /// How many older chats are merged under this one.
    public var mergedCount = 0
    /// Whether the chat is archived, and so listed nowhere but here.
    public var isArchived = false

    public var id: String { chat.id }

    public init(chat: IndexedChat, snippet: String? = nil, mergedCount: Int = 0, isArchived: Bool = false) {
        self.chat = chat
        self.snippet = snippet
        self.mergedCount = mergedCount
        self.isArchived = isArchived
    }
}
