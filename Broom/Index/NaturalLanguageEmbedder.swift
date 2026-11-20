import NaturalLanguage

/// Apple's on-device English sentence embedding. Nothing leaves the Mac and no model is downloaded.
///
/// On ten technical sentence pairs, related pairs scored 0.48 to 0.73 (cosine similarity) and unrelated ones 0.25 to
/// 0.35. The gap is real but narrow, so callers rank by it and do not treat a threshold as certain.
public struct NaturalLanguageEmbedder: SentenceEmbedder {
    public init() {}

    public func vector(for text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        return embedding.vector(for: trimmed).map { $0.map(Float.init) }
    }
}
