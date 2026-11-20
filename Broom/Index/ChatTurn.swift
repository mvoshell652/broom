import Foundation

/// One thing said in a chat: a prompt the user typed or a reply Claude wrote. Tool calls and their output are not turns.
public struct ChatTurn: Equatable, Sendable {
    public var role: ChatRole
    public var text: String
    public var date: Date?

    public init(role: ChatRole, text: String, date: Date? = nil) {
        self.role = role
        self.text = text
        self.date = date
    }
}
