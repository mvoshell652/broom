import Foundation

/// One line of a before/after comparison.
struct DiffLine: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case unchanged
        case added
        case removed
        /// Stands for a run of unchanged lines that is not shown.
        case gap
    }

    let id: Int
    var kind: Kind
    var text: String

    /// The line as a unified diff shows it: `+`, `-` or a space in front.
    var marked: String {
        switch kind {
        case .unchanged: "  " + text
        case .added: "+ " + text
        case .removed: "- " + text
        case .gap: "  ⋯"
        }
    }

    /// Compares two texts line by line, keeping `context` unchanged lines around each change.
    static func lines(from old: String, to new: String, context: Int = 3) -> [DiffLine] {
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let difference = newLines.difference(from: oldLines)
        var removed = Set<Int>(), added = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }

        var all: [(kind: Kind, text: String)] = []
        var oldIndex = 0, newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removed.contains(oldIndex) {
                all.append((.removed, oldLines[oldIndex]))
                oldIndex += 1
            } else if newIndex < newLines.count, added.contains(newIndex) {
                all.append((.added, newLines[newIndex]))
                newIndex += 1
            } else {
                all.append((.unchanged, newLines[newIndex]))
                oldIndex += 1
                newIndex += 1
            }
        }

        // Keep changed lines and the unchanged lines within `context` of one; collapse the rest.
        let changed = all.indices.filter { all[$0].kind != .unchanged }
        var keep = Set<Int>()
        for index in changed {
            keep.formUnion(max(0, index - context)...min(all.count - 1, index + context))
        }
        var result: [DiffLine] = []
        for index in all.indices {
            if keep.contains(index) {
                result.append(DiffLine(id: result.count, kind: all[index].kind, text: all[index].text))
            } else if result.last?.kind != .gap, !changed.isEmpty {
                result.append(DiffLine(id: result.count, kind: .gap, text: ""))
            }
        }
        return result
    }
}
