/// A topic the user's chats are filed under. It starts as a project folder's name and the user can rename it.
public struct Workstream: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}
