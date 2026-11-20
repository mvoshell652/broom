import Foundation

/// One recorded change as the History tab shows it: what was done, where, and to which chats.
public struct HistoryItem: Identifiable, Equatable, Sendable {
    public var entry: OrganizerLogEntry
    /// What happened, starting with the verb: "Merged 2 chats in mobile", "Marked “Fix the build” done".
    public var headline: String
    /// The chats the change touched, when there were several. A change to one chat names it in the headline.
    public var chats: [IndexedChat]

    public var id: Int64 { entry.id }
    public var date: Date { entry.date }

    public init(entry: OrganizerLogEntry, headline: String, chats: [IndexedChat] = []) {
        self.entry = entry
        self.headline = headline
        self.chats = chats
    }

    /// Describes `entry`, looking its chats up in `chatsByID`. A chat no longer in the index is still counted.
    public init(entry: OrganizerLogEntry, chatsByID: [String: IndexedChat]) {
        func many(_ verb: String, _ ids: [String], _ after: String = "") -> (String, [IndexedChat]) {
            let chats = ids.compactMap { chatsByID[$0] }
            let count = ids.count == 1 ? "1 chat" : "\(ids.count) chats"
            return ("\(verb) \(count)\(after)\(Self.place(of: chats))", chats)
        }
        func one(_ id: String, _ make: (String) -> String) -> (String, [IndexedChat]) {
            (make(Self.quoted(chatsByID[id]?.title)), [])
        }
        let (headline, chats): (String, [IndexedChat]) = switch entry.change {
        case .merged(let previousGroups): many("Merged", previousGroups.keys.sorted())
        case .markedDistinct(let ids): many("Kept", ids, " apart")
        case .archived(let ids): many("Archived", ids)
        case .closedLoop(let id, _): one(id) { "Marked \($0) done" }
        case .filed, .createdWorkstream: (entry.summary, [])
        }
        self.init(entry: entry, headline: headline, chats: chats.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) })
    }

    /// " in mobile" when every chat ran in the same project, else nothing.
    private static func place(of chats: [IndexedChat]) -> String {
        let projects = Set(chats.compactMap { $0.cwd.map(ProjectFolder.root(of:)) })
        guard projects.count == 1, let project = projects.first else { return "" }
        return " in \(ProjectFolder.name(of: project))"
    }

    private static func quoted(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "a chat" }
        return "“\(title)”"
    }
}
