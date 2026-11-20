import Foundation

/// Where Claude Code keeps its files.
public enum ClaudePaths {
    /// The directory holding one folder of transcripts per project: `~/.claude/projects`, or under `CLAUDE_CONFIG_DIR` when set.
    public static func projectsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        configDirectory(environment: environment, homeDirectory: homeDirectory).appending(path: "projects")
    }

    /// The user-level settings file: `~/.claude/settings.json`, or under `CLAUDE_CONFIG_DIR` when set.
    public static func settingsFile(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        configDirectory(environment: environment, homeDirectory: homeDirectory).appending(path: "settings.json")
    }

    private static func configDirectory(environment: [String: String], homeDirectory: URL) -> URL {
        environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? homeDirectory.appending(path: ".claude")
    }
}
