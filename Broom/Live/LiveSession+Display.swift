import BroomCore

extension LiveSession {
    /// The title to show: the session's own, or its folder when it has none yet.
    var displayTitle: String {
        title.isEmpty ? (repoName ?? "Untitled session") : title
    }
}
