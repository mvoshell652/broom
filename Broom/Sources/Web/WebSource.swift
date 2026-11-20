/// claude.ai chats, reported by a browser companion. Not built in v0: the stream is always empty.
public struct WebSource: SessionSource {
    /// Web chats.
    public let kind = SessionSourceKind.web

    public init() {}

    /// An empty stream that ends at once.
    public func events() -> AsyncStream<SessionEvent> {
        AsyncStream { $0.finish() }
    }
}
