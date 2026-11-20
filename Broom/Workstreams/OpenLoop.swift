/// A chat that was left with something still to do.
public struct OpenLoop: Identifiable, Equatable, Sendable {
    public var chat: IndexedChat
    public var kind: OpenLoopKind
    /// The workstream the chat is filed under, if any.
    public var workstreamName: String?

    public var id: String { chat.id }

    public init(chat: IndexedChat, kind: OpenLoopKind, workstreamName: String? = nil) {
        self.chat = chat
        self.kind = kind
        self.workstreamName = workstreamName
    }
}
