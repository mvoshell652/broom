import Foundation

/// The project a chat's working directory belongs to.
public enum ProjectFolder {
    /// The project folder for `cwd`: the repository a Claude Code worktree was made from, or `cwd` itself.
    public static func root(of cwd: String) -> String {
        guard let marker = cwd.range(of: worktreeMarker) else { return cwd }
        return String(cwd[..<marker.lowerBound])
    }

    /// The folder's own name, which a workstream seeded from it starts with.
    public static func name(of root: String) -> String {
        let name = URL(fileURLWithPath: root).lastPathComponent
        return name.isEmpty || name == "/" ? root : name
    }

    /// Claude Code keeps a repository's worktrees here, inside the repository.
    private static let worktreeMarker = "/.claude/worktrees/"
}
