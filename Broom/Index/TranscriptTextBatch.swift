import Foundation

/// What a stretch of a transcript file contained, for the chat index.
public struct TranscriptTextBatch: Equatable, Sendable {
    /// The prompts and replies found, in file order.
    public var turns: [ChatTurn] = []
    /// The chat's title, when the stretch set one.
    public var customTitle: String?
    /// The folder the chat ran in, when the stretch named one.
    public var cwd: String?
    /// How many bytes were read through the last complete line. Reading resumes after them.
    public var consumedByteCount = 0
}
