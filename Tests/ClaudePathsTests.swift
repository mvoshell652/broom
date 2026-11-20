import Foundation
import Testing
@testable import BroomCore

@Suite("ClaudePaths")
struct ClaudePathsTests {
    private let home = URL(fileURLWithPath: "/Users/dev")

    @Test("Transcripts are under ~/.claude/projects by default")
    func defaultLocation() {
        #expect(ClaudePaths.projectsDirectory(environment: [:], homeDirectory: home).path == "/Users/dev/.claude/projects")
    }

    @Test("CLAUDE_CONFIG_DIR moves the projects directory")
    func configDirectoryOverride() {
        let directory = ClaudePaths.projectsDirectory(environment: ["CLAUDE_CONFIG_DIR": "/Volumes/work/claude"], homeDirectory: home)

        #expect(directory.path == "/Volumes/work/claude/projects")
    }

    @Test("The settings file is next to the projects directory")
    func settingsFile() {
        #expect(ClaudePaths.settingsFile(environment: [:], homeDirectory: home).path == "/Users/dev/.claude/settings.json")
        #expect(ClaudePaths.settingsFile(environment: ["CLAUDE_CONFIG_DIR": "/Volumes/work/claude"], homeDirectory: home).path
            == "/Volumes/work/claude/settings.json")
    }

    @Test("An empty CLAUDE_CONFIG_DIR is ignored")
    func emptyOverride() {
        #expect(ClaudePaths.projectsDirectory(environment: ["CLAUDE_CONFIG_DIR": ""], homeDirectory: home).path == "/Users/dev/.claude/projects")
    }
}
