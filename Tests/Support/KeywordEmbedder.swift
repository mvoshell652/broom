import Foundation
@testable import BroomCore

/// A stand-in embedder for tests: one dimension per topic word, so "close in meaning" is exact and repeatable.
struct KeywordEmbedder: SentenceEmbedder {
    /// Words that mean the same topic share a dimension.
    let topics: [[String]]

    func vector(for text: String) -> [Float]? {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        let vector = topics.map { topic in topic.contains { words.contains($0) } ? Float(1) : 0 }
        return vector.contains(1) ? vector : nil
    }
}
