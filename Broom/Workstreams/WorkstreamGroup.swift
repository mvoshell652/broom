import Foundation

/// A workstream with the chats filed under it, for the Workstreams tab.
public struct WorkstreamGroup: Identifiable, Equatable, Sendable {
    public var workstream: Workstream
    /// Its chats as the tab lists them, merged ones stacked, most recently active first.
    public var stacks: [ChatStack]

    public var id: Int64 { workstream.id }

    /// Every chat in the workstream, merged ones included.
    public var chats: [IndexedChat] { stacks.flatMap(\.all) }

    /// When any of its chats was last active, or `nil` when it has none.
    public var lastActivityAt: Date? {
        stacks.first?.chat.lastActivityAt
    }

    public init(workstream: Workstream, stacks: [ChatStack]) {
        self.workstream = workstream
        self.stacks = stacks
    }

    /// A workstream of unmerged chats, most recently active first.
    public init(workstream: Workstream, chats: [IndexedChat]) {
        self.init(workstream: workstream, stacks: chats.map { ChatStack(chat: $0) })
    }
}
