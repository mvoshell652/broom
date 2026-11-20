/// Two chats, in no particular order. The user's "Not the same" is stored as pairs.
public struct ChatPair: Hashable, Sendable {
    public let first: String
    public let second: String

    /// The pair of `a` and `b`; `ChatPair("x", "y") == ChatPair("y", "x")`.
    public init(_ a: String, _ b: String) {
        first = min(a, b)
        second = max(a, b)
    }
}
