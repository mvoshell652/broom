/// Why chats are thought to be duplicates.
public enum DuplicateKind: Sendable {
    /// They start with the same prompt, word for word.
    case identical
    /// They start differently but mean nearly the same.
    case similar
}
