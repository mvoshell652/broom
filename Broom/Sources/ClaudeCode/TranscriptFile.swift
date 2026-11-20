import Foundation

/// What a path under the projects directory is.
public enum TranscriptFile: Equatable, Sendable {
    /// `<project>/<session-id>.jsonl`
    case session(id: String)
    /// `<project>/<session-id>/subagents/<anything>.jsonl`
    case subagent(parentSessionID: String)

    /// Classifies `path`, or returns `nil` for anything that is not a live transcript, including set-aside files.
    ///
    /// Both paths must already have their symlinks resolved.
    public init?(path: String, projectsDirectory: String) {
        let root = projectsDirectory.hasSuffix("/") ? projectsDirectory : projectsDirectory + "/"
        guard path.hasPrefix(root), path.hasSuffix(".jsonl") else { return nil }
        let components = path.dropFirst(root.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        switch components.count {
        case 2:
            let name = String(components[1].dropLast(".jsonl".count))
            guard Self.isSessionID(name) else { return nil }
            self = .session(id: name)
        case 4 where components[2] == "subagents" && Self.isSessionID(components[1]):
            self = .subagent(parentSessionID: components[1])
        default:
            return nil
        }
    }

    /// Session ids are UUIDs, which also rules out `<id>.orphaned-…` and `<id>.jsonl.superseded-…`.
    private static func isSessionID(_ name: String) -> Bool {
        name.count == 36 && UUID(uuidString: name) != nil
    }
}
