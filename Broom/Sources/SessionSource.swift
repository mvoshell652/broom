/// Something that reports session activity: Claude Code today, web chats later.
public protocol SessionSource: Sendable {
    var kind: SessionSourceKind { get }

    /// Starts observing and returns the events as they happen. Ending the stream's consumer stops the observation.
    ///
    /// A source supports one consumer: call this once per source.
    func events() -> AsyncStream<SessionEvent>
}
