import Foundation

/// Chats that look like the same conversation started more than once.
public struct DuplicateGroup: Identifiable, Equatable, Sendable {
    public var kind: DuplicateKind
    /// The chats, most recently active first.
    public var chats: [IndexedChat]

    public var id: String { chats.map(\.id).sorted().joined(separator: "+") }

    /// What the chats are about: the newest one's title.
    public var topic: String { chats.first?.title ?? "" }

    /// When the earliest of them began.
    public var since: Date? {
        chats.compactMap { $0.startedAt ?? $0.lastActivityAt }.min()
    }

    public init(kind: DuplicateKind, chats: [IndexedChat]) {
        self.kind = kind
        self.chats = chats
    }
}
