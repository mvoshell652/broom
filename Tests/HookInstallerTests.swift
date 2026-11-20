import Foundation
import Testing
@testable import Broom

/// Hook install shows a diff, writes a backup, preserves existing hooks, and Disconnect restores the original hook set.
/// Every test works on a file in a temp folder; none touches the real `~/.claude/settings.json`.
@Suite("HookInstaller")
struct HookInstallerTests {
    private let scratch: TemporaryDirectory
    private var directory: URL { scratch.url }
    private let settings: URL
    /// A stand-in helper that exists, inside a folder shaped like an app bundle.
    private let helper: String
    private var installer: HookInstaller { HookInstaller(settingsURL: settings, helperPath: helper) }

    /// A realistic settings file: other keys, another tool's hooks on events Broom also uses, and one it does not.
    private let existing = """
        {
          "model": "opus",
          "permissions": {
            "allow": [
              "Bash(swift build:*)"
            ]
          },
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "/usr/local/bin/audit-bash"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "say done",
                    "timeout": 5
                  }
                ]
              }
            ],
            "PreCompact": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "echo compacting"
                  }
                ]
              }
            ]
          },
          "env": {
            "FOO": "1"
          }
        }

        """

    init() throws {
        let scratch = try TemporaryDirectory(prefix: "broom-installer")
        self.scratch = scratch
        settings = scratch.url.appending(path: "settings.json")
        helper = try Self.makeHelper(at: scratch.url.appending(path: "Broom.app/Contents/Helpers/broom-hook"))
    }

    /// Creates an executable file at `url` and returns its path.
    private static func makeHelper(at url: URL) throws -> String {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: settings)
    }

    private func read() throws -> String {
        try String(contentsOf: settings, encoding: .utf8)
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".broom-backup-") }.sorted()
    }

    private func commands(for event: String, in text: String) throws -> [String] {
        guard case .array(let groups)? = try JSONParser.parse(text)["hooks"]?[event] else { return [] }
        return groups.flatMap { group -> [String] in
            guard case .array(let hooks)? = group["hooks"] else { return [] }
            return hooks.compactMap { hook in
                if case .string(let command)? = hook["command"] { command } else { nil }
            }
        }
    }

    // MARK: - Connect

    @Test("Planning writes nothing and shows only added lines")
    func planIsReadOnly() throws {
        try write(existing)

        let plan = try installer.plan(.connect)

        #expect(try read() == existing)
        #expect(try backups().isEmpty)
        #expect(plan.hasChanges)
        #expect(!plan.diff.contains { $0.kind == .removed })
        #expect(plan.diff.contains { $0.kind == .added && $0.text.contains(helper) })
    }

    @Test("Connecting adds the helper to all ten events and keeps every existing hook and setting")
    func connectPreservesExistingHooks() throws {
        try write(existing)

        try installer.apply(installer.plan(.connect))
        let result = try read()

        for event in HookInstaller.events {
            #expect(try commands(for: event, in: result).contains(helper), "\(event)")
        }
        #expect(HookInstaller.events.count == 10)
        // Other tools' hooks are still there, ahead of Broom's.
        #expect(try commands(for: "PreToolUse", in: result) == ["/usr/local/bin/audit-bash", helper])
        #expect(try commands(for: "Stop", in: result) == ["say done", helper])
        #expect(try commands(for: "PreCompact", in: result) == ["echo compacting"])
        let parsed = try JSONParser.parse(result)
        #expect(parsed["model"] == .string("opus"))
        #expect(parsed["env"]?["FOO"] == .string("1"))
        #expect(installer.isInstalled())
    }

    @Test("Broom's entry has no matcher and a 2 second timeout")
    func entryShape() throws {
        try installer.apply(installer.plan(.connect))

        let group = try #require({ () -> JSONValue? in
            guard case .array(let groups)? = try JSONParser.parse(try read())["hooks"]?["SessionStart"] else { return nil }
            return groups.first
        }())

        #expect(group == .object([.init(key: "hooks", value: .array([.object([
            .init(key: "type", value: .string("command")),
            .init(key: "command", value: .string(helper)),
            .init(key: "timeout", value: .number("2")),
        ])]))]))
    }

    @Test("The backup holds the file exactly as it was")
    func backup() throws {
        try write(existing)
        let stamp = Date(timeIntervalSince1970: 1_794_650_400)

        let backupURL = try #require(try installer.apply(installer.plan(.connect), now: stamp))

        #expect(try String(contentsOf: backupURL, encoding: .utf8) == existing)
        #expect(backupURL.lastPathComponent.hasPrefix("settings.json.broom-backup-2026"))
        #expect(try backups() == [backupURL.lastPathComponent])
    }

    @Test("With no settings file, one is created and there is nothing to back up")
    func missingFile() throws {
        let plan = try installer.plan(.connect)
        #expect(plan.currentText == nil)
        #expect(plan.diff.allSatisfy { $0.kind == .added })

        let backupURL = try installer.apply(plan)

        #expect(backupURL == nil)
        #expect(installer.isInstalled())
    }

    @Test("An empty settings file is treated as an empty object")
    func emptyFile() throws {
        try write("")

        try installer.apply(installer.plan(.connect))

        #expect(installer.isInstalled())
    }

    @Test("Connecting twice changes nothing the second time")
    func idempotent() throws {
        try write(existing)
        try installer.apply(installer.plan(.connect))
        let connected = try read()

        let second = try installer.plan(.connect)

        #expect(!second.hasChanges)
        #expect(second.diff.isEmpty)
        #expect(try installer.apply(second) == nil)
        #expect(try read() == connected)
        #expect(try backups().count == 1)
    }

    @Test("A partial install is completed without duplicating what is there")
    func partialInstall() throws {
        try installer.apply(installer.plan(.connect))
        var value = try JSONParser.parse(try read())
        var hooks = try #require(value["hooks"])
        hooks["Stop"] = nil
        value["hooks"] = hooks
        try write(value.text() + "\n")
        #expect(!installer.isInstalled())

        try installer.apply(installer.plan(.connect))

        #expect(installer.isInstalled())
        #expect(try commands(for: "SessionStart", in: try read()) == [helper])
    }

    // MARK: - Disconnect

    @Test("Disconnecting after connecting gives back the original file, byte for byte")
    func disconnectRestoresOriginal() throws {
        try write(existing)
        try installer.apply(installer.plan(.connect))

        let plan = try installer.plan(.disconnect)
        try installer.apply(plan)

        #expect(!plan.diff.contains { $0.kind == .added })
        #expect(try read() == existing)
        #expect(!installer.isInstalled())
        #expect(try backups().count == 2)
    }

    @Test("Disconnecting from a file that had no hooks removes the hooks key again")
    func disconnectRemovesEmptyHooks() throws {
        let original = "{\n  \"model\": \"opus\"\n}\n"
        try write(original)
        try installer.apply(installer.plan(.connect))

        try installer.apply(installer.plan(.disconnect))

        #expect(try read() == original)
    }

    @Test("Disconnecting removes only the helper from a group that also runs something else")
    func disconnectSharedGroup() throws {
        try write("""
            {
              "hooks": {
                "Stop": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "say done"
                      },
                      {
                        "type": "command",
                        "command": "\(helper)"
                      }
                    ]
                  }
                ]
              }
            }

            """)

        try installer.apply(installer.plan(.disconnect))

        #expect(try commands(for: "Stop", in: try read()) == ["say done"])
    }

    @Test("Disconnecting when nothing is installed changes nothing")
    func disconnectNotInstalled() throws {
        try write(existing)

        let plan = try installer.plan(.disconnect)

        #expect(!plan.hasChanges)
        #expect(try installer.apply(plan) == nil)
        #expect(try read() == existing)
    }

    @Test("Disconnect also removes the helper of a Broom.app that has since moved")
    func disconnectMovedApp() throws {
        let oldHelper = try Self.makeHelper(at: directory.appending(path: "Downloads/Broom.app/Contents/Helpers/broom-hook"))
        let old = HookInstaller(settingsURL: settings, helperPath: oldHelper)
        try old.apply(old.plan(.connect))

        try installer.apply(installer.plan(.disconnect))

        #expect(try read() == "{}\n")
    }

    @Test("Disconnect also removes the helper of a development build")
    func disconnectDevelopmentBuild() throws {
        let devHelper = try Self.makeHelper(at: directory.appending(path: "repo/.build/debug/broom-hook"))
        let dev = HookInstaller(settingsURL: settings, helperPath: devHelper)
        try write(existing)
        try dev.apply(dev.plan(.connect))

        try installer.apply(installer.plan(.disconnect))

        #expect(try read() == existing)
    }

    @Test("Connecting repoints entries left by another copy of Broom instead of adding a second set")
    func connectRepointsStaleEntries() throws {
        let oldHelper = try Self.makeHelper(at: directory.appending(path: "Downloads/Broom.app/Contents/Helpers/broom-hook"))
        let old = HookInstaller(settingsURL: settings, helperPath: oldHelper)
        try write(existing)
        try old.apply(old.plan(.connect))
        // The settings name the old copy, so this copy is not connected yet.
        #expect(!installer.isInstalled())

        try installer.apply(installer.plan(.connect))
        let result = try read()

        #expect(installer.isInstalled())
        #expect(!result.contains(oldHelper))
        for event in HookInstaller.events {
            #expect(try commands(for: event, in: result).filter { $0.hasSuffix("broom-hook") } == [helper], "\(event)")
        }
        #expect(try commands(for: "Stop", in: result) == ["say done", helper])
    }

    @Test("Commands that merely mention broom-hook are not taken for Broom's", arguments: [
        "echo /tmp/broom-hook", "/usr/local/bin/broom-hook --verbose", "broom-hook", "/opt/tools/not-broom-hook-at-all/run",
        "sh -c '/Applications/Broom.app/Contents/Helpers/broom-hook'",
    ])
    func otherCommandsAreKept(command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        try write("{\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          {\n            \"type\": \"command\",\n            \"command\": \"\(escaped)\"\n          }\n        ]\n      }\n    ]\n  }\n}\n")
        let original = try read()

        #expect(try !installer.plan(.disconnect).hasChanges)
        try installer.apply(installer.plan(.connect))
        try installer.apply(installer.plan(.disconnect))

        #expect(try read() == original)
    }

    @Test("Disconnecting leaves an empty hooks object alone when nothing of Broom's is there")
    func disconnectKeepsEmptyHooks() throws {
        try write("{\n  \"hooks\": {},\n  \"a\": 1\n}\n")

        #expect(try !installer.plan(.disconnect).hasChanges)
    }

    @Test("The file's own indentation, line endings and final newline are kept", arguments: [
        "{\n\t\"model\": \"opus\",\n\t\"env\": {\n\t\t\"FOO\": \"1\"\n\t}\n}\n",
        "{\n    \"model\": \"opus\",\n    \"env\": {\n        \"FOO\": \"1\"\n    }\n}",
        "{\r\n  \"model\": \"opus\",\r\n  \"env\": {\r\n    \"FOO\": \"1\"\r\n  }\r\n}\r\n",
    ])
    func formattingIsKept(original: String) throws {
        try write(original)

        let plan = try installer.plan(.connect)
        // Only additions: nothing the user wrote is re-laid-out.
        #expect(!plan.diff.contains { $0.kind == .removed })
        try installer.apply(plan)
        #expect(installer.isInstalled())
        try installer.apply(installer.plan(.disconnect))

        #expect(try read() == original)
    }

    @Test("Connecting is refused when the helper file is missing, so dead hooks are never written")
    func helperMissing() throws {
        try write(existing)
        let broken = HookInstaller(settingsURL: settings, helperPath: directory.appending(path: "nowhere/broom-hook").path)

        #expect(throws: HookInstaller.Failure.helperMissing) {
            try broken.plan(.connect)
        }
        #expect(try read() == existing)
        // Disconnecting still works without the helper.
        #expect(try !broken.plan(.disconnect).hasChanges)
    }

    @Test("A read-only settings file is not replaced")
    func readOnlyFile() throws {
        try write(existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: settings.path)
        let plan = try installer.plan(.connect)

        #expect(throws: HookInstaller.Failure.notWritable) {
            try installer.apply(plan)
        }
        #expect(try read() == existing)
        #expect(try backups().isEmpty)
    }

    @Test("A symlink whose target is missing is left alone")
    func danglingSymlink() throws {
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: directory.appending(path: "dotfiles/missing.json"))

        #expect(throws: HookInstaller.Failure.notWritable) {
            try installer.plan(.connect)
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path).hasSuffix("dotfiles/missing.json"))
    }

    // MARK: - Safety

    @Test("A file that changed after the plan was shown is not overwritten")
    func changedSinceReview() throws {
        try write(existing)
        let plan = try installer.plan(.connect)
        let edited = existing.replacingOccurrences(of: "opus", with: "sonnet")
        try write(edited)

        #expect(throws: HookInstaller.Failure.changedSinceReview) {
            try installer.apply(plan)
        }
        #expect(try read() == edited)
        #expect(try backups().isEmpty)
    }

    @Test("Settings that are not valid JSON, or whose hooks have an unexpected shape, are left alone", arguments: [
        "{ not json", "[1, 2]", "{\"hooks\": []}", "{\"hooks\": {\"Stop\": {}}}", "{\"model\": \"opus\",}",
        "{\"hooks\": {}, \"hooks\": {}}",
    ])
    func unreadableSettings(text: String) throws {
        try write(text)

        #expect(throws: HookInstaller.Failure.unreadableSettings) {
            try installer.plan(.connect)
        }
        #expect(try read() == text)
        #expect(!installer.isInstalled())
    }

    @Test("The file keeps its permissions")
    func permissions() throws {
        try write(existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)

        try installer.apply(installer.plan(.connect))

        #expect(try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test("A symlinked settings file stays a symlink and its target is updated")
    func symlink() throws {
        let target = directory.appending(path: "dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(existing.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: target)

        try installer.apply(installer.plan(.connect))

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8).contains(helper))
    }

    @Test("A helper path with spaces is shell-quoted, and still recognised afterwards")
    func quoting() throws {
        let spacedHelper = try Self.makeHelper(at: directory.appending(path: "My Apps/Broom.app/Contents/Helpers/broom-hook"))
        let spaced = HookInstaller(settingsURL: settings, helperPath: spacedHelper)
        #expect(spaced.command == "'\(spacedHelper)'")
        #expect(HookInstaller.shellQuoted("/it's/here") == "'/it'\\''s/here'")
        #expect(HookInstaller.shellQuoted("/plain/path-1.2_x") == "/plain/path-1.2_x")

        try spaced.apply(spaced.plan(.connect))

        #expect(spaced.isInstalled())
        try spaced.apply(spaced.plan(.disconnect))
        #expect(try read() == "{}\n")
    }
}
