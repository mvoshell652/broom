import Accelerate
import Foundation

/// Small helpers for comparing embedding vectors.
public enum VectorMath {
    /// How alike two vectors point, from -1 to 1. Zero when either is empty, all zeros, or they differ in length.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = vDSP.dot(a, b)
        let magnitudes = (vDSP.sumOfSquares(a) * vDSP.sumOfSquares(b)).squareRoot()
        return magnitudes > 0 ? dot / magnitudes : 0
    }

    /// Packs a vector into bytes for storage.
    public static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Unpacks a stored vector.
    public static func vector(from data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
