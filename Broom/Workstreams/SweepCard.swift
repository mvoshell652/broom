/// One suggestion in the weekly sweep, which the user accepts or skips.
public enum SweepCard: Identifiable, Equatable, Sendable {
    /// Chats that look like the same conversation, to merge into one row.
    case merge(DuplicateGroup)
    /// A project's chats that have been quiet for 90 days and were not left open, to archive.
    case archive(workstream: Workstream, chats: [IndexedChat])
    /// A chat left unfinished, to go back to.
    case revisit(OpenLoop)

    /// Stable for as long as the suggestion is the same one, so a skip can be remembered.
    public var id: String {
        switch self {
        case .merge(let group): "merge:\(group.id)"
        case .archive(let workstream, _): "archive:\(workstream.id)"
        case .revisit(let loop): "revisit:\(loop.id)"
        }
    }

    public var kind: SweepCardKind {
        switch self {
        case .merge: .merge
        case .archive: .archive
        case .revisit: .revisit
        }
    }
}
