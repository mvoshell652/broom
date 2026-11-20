/// A chat as the lists show it: one chat, or several the user merged, with the newest on top.
public struct ChatStack: Identifiable, Equatable, Sendable {
    /// The chat the row stands for: the most recently active of those merged.
    public var chat: IndexedChat
    /// The older chats merged under it, most recently active first. Empty for a chat that is not merged.
    public var merged: [IndexedChat]

    public var id: String { chat.id }

    /// Every chat in the stack, newest first.
    public var all: [IndexedChat] { [chat] + merged }

    public init(chat: IndexedChat, merged: [IndexedChat] = []) {
        self.chat = chat
        self.merged = merged
    }
}
