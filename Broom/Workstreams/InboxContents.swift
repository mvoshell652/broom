/// What the Inbox tab lists: chats that look like duplicates, and chats left unfinished.
public struct InboxContents: Equatable, Sendable {
    public var duplicates: [DuplicateGroup]
    public var openLoops: [OpenLoop]

    /// The number on the Inbox tab.
    public var count: Int { duplicates.count + openLoops.count }

    public var isEmpty: Bool { count == 0 }

    public init(duplicates: [DuplicateGroup] = [], openLoops: [OpenLoop] = []) {
        self.duplicates = duplicates
        self.openLoops = openLoops
    }
}
