import Foundation

/// Finds chats that look like the same conversation started more than once.
public enum DuplicateFinder {
    /// The duplicate groups among `chats`, the most recently active group first.
    ///
    /// Two kinds are found separately: chats that open with the same prompt word for word, in groups of any size, and
    /// chats whose openings differ but mean nearly the same, in groups of up to five. A larger group of similar
    /// openings is a shared preamble, not a repeated conversation, so it is left out.
    ///
    /// - Parameters:
    ///   - chats: The chats to compare. Those quiet for longer than `window` are ignored.
    ///   - vectors: Each chat's vector, by chat id.
    ///   - openings: The text each chat's vector was made from, by chat id.
    ///   - mergeGroups: The merge group of each merged chat, by chat id. Chats already merged together are not paired.
    ///   - distinct: Pairs the user said are not the same.
    public static func groups(
        among chats: [IndexedChat], vectors: [String: [Float]], openings: [String: String],
        mergeGroups: [String: String] = [:], distinct: Set<ChatPair> = [], now: Date
    ) -> [DuplicateGroup] {
        let recent = chats
            .filter { chat in chat.lastActivityAt.map { now.timeIntervalSince($0) <= window } ?? false }
            .sorted { ($0.lastActivityAt ?? .distantPast, $0.id) > ($1.lastActivityAt ?? .distantPast, $1.id) }
        var identical = Components(count: recent.count)
        var similar = Components(count: recent.count)
        for first in recent.indices {
            for second in recent.indices where second > first {
                let a = recent[first], b = recent[second]
                if let group = mergeGroups[a.id], group == mergeGroups[b.id] { continue }
                if distinct.contains(ChatPair(a.id, b.id)) { continue }
                if let opening = openings[a.id], !opening.isEmpty, opening == openings[b.id] {
                    identical.join(first, second)
                } else if let vectorA = vectors[a.id], let vectorB = vectors[b.id],
                          VectorMath.cosineSimilarity(vectorA, vectorB) >= minimumSimilarity {
                    similar.join(first, second)
                }
            }
        }
        let groups = identical.groups().map { DuplicateGroup(kind: .identical, chats: $0.map { recent[$0] }) }
            + similar.groups().filter { $0.count <= maximumSimilarGroupSize }.map { DuplicateGroup(kind: .similar, chats: $0.map { recent[$0] }) }
        return groups.sorted { first, second in
            (first.chats.first?.lastActivityAt ?? .distantPast, first.id) > (second.chats.first?.lastActivityAt ?? .distantPast, second.id)
        }
    }

    /// How far back duplicates are looked for.
    static let window: TimeInterval = 30 * 24 * 3600
    /// Openings at least this alike count as the same subject. Unrelated text measured 0.25 to 0.35 and related text
    /// 0.48 to 0.73, so this asks for much more than "related".
    static let minimumSimilarity: Float = 0.9
    static let maximumSimilarGroupSize = 5
}

/// Disjoint sets over the indices `0..<count`, for grouping items joined in pairs.
private struct Components {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    private mutating func root(of index: Int) -> Int {
        var index = index
        while parent[index] != index {
            parent[index] = parent[parent[index]]
            index = parent[index]
        }
        return index
    }

    mutating func join(_ first: Int, _ second: Int) {
        parent[root(of: first)] = root(of: second)
    }

    /// The sets with more than one member, each in ascending index order.
    mutating func groups() -> [[Int]] {
        var members: [Int: [Int]] = [:]
        for index in parent.indices {
            members[root(of: index), default: []].append(index)
        }
        return members.values.filter { $0.count > 1 }.sorted { $0[0] < $1[0] }
    }
}
