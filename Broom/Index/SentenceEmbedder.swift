/// Turns a piece of text into a vector, so that texts about the same thing land close together.
public protocol SentenceEmbedder: Sendable {
    /// The vector for `text`, or `nil` when it cannot be embedded (empty, or a language the model does not cover).
    func vector(for text: String) -> [Float]?
}
