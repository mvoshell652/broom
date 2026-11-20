import Foundation

/// Adds Broom's hooks to Claude Code's `settings.json`, and removes them again.
///
/// Nothing is written without a `Plan` the caller has shown to the user, and every write is preceded by a backup.
struct HookInstaller: Sendable {
    /// The hook events Broom listens to.
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse",
        "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd",
    ]
    /// Seconds Claude Code waits for the helper. The helper stops itself after 300 ms.
    static let timeout = 2

    enum Change: Sendable {
        case connect
        case disconnect
    }

    /// A reviewed change to the settings file: what is there now and what would be written.
    struct Plan: Identifiable, Equatable, Sendable {
        let id = UUID()
        var change: Change
        /// The file's text when the plan was made, or `nil` if it did not exist.
        var currentText: String?
        var proposedText: String
        var diff: [DiffLine]

        /// Whether applying the plan would change the file.
        var hasChanges: Bool {
            currentText != proposedText
        }
    }

    enum Failure: Error, Equatable {
        /// The settings file is not valid JSON, or its `hooks` are not in the documented shape. It is left untouched.
        case unreadableSettings
        /// The file changed after the plan was shown. Nothing was written; make a new plan.
        case changedSinceReview
        /// The settings file is read-only, or is a symlink to a file that does not exist. It is left untouched.
        case notWritable
        /// `broom-hook` is not at the path the hooks would point to, so connecting would install hooks that always fail.
        case helperMissing
    }

    /// The settings file. A symlink is followed, so a dotfiles setup keeps its link.
    let settingsURL: URL
    /// The command Claude Code runs for each hook: the path of `broom-hook`, shell-quoted.
    let command: String
    private let helperPath: String
    /// The path as given, before following a symlink.
    private let givenURL: URL

    init(settingsURL: URL, helperPath: String) {
        self.givenURL = settingsURL
        self.settingsURL = settingsURL.resolvingSymlinksInPath()
        self.helperPath = helperPath
        self.command = Self.shellQuoted(helperPath)
    }

    // MARK: - Reading

    /// Whether every hook event runs Broom's helper.
    func isInstalled() -> Bool {
        guard let settings = try? currentSettings().value else { return false }
        return Self.events.allSatisfy { event in
            guard case .array(let groups)? = settings["hooks"]?[event] else { return false }
            return groups.contains { group in
                guard case .array(let hooks)? = group["hooks"] else { return false }
                return hooks.contains(where: isCurrentHook)
            }
        }
    }

    /// Works out the change without writing anything.
    func plan(_ change: Change) throws -> Plan {
        if change == .connect, !FileManager.default.isExecutableFile(atPath: helperPath) {
            throw Failure.helperMissing
        }
        let current = try currentSettings()
        var settings = current.value
        switch change {
        case .connect: try addHooks(to: &settings)
        case .disconnect: try removeHooks(from: &settings)
        }
        // An unchanged document keeps the file's own text, so an untouched file shows no diff.
        let proposed = settings == current.value
            ? (current.text ?? "{}\n")
            : Self.text(of: settings, formattedLike: current.text)
        return Plan(
            change: change, currentText: current.text, proposedText: proposed,
            diff: DiffLine.lines(from: current.text ?? "", to: proposed)
        )
    }

    // MARK: - Writing

    /// Writes a reviewed plan. Returns the backup's location, or `nil` when there was no file to back up or nothing to change.
    @discardableResult
    func apply(_ plan: Plan, now: Date = Date()) throws -> URL? {
        guard try currentSettings().text == plan.currentText else { throw Failure.changedSinceReview }
        guard plan.hasChanges else { return nil }

        let fileManager = FileManager.default
        if plan.currentText != nil, !fileManager.isWritableFile(atPath: settingsURL.path) {
            // An atomic write would replace a file the user made read-only on purpose.
            throw Failure.notWritable
        }
        var backup: URL?
        var permissions: Any?
        if plan.currentText != nil {
            let stamp = now.formatted(.verbatim(
                "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                timeZone: .current, calendar: .init(identifier: .gregorian)
            ))
            // Never overwrite an earlier backup: two changes in one second get distinct names.
            var url = URL(fileURLWithPath: settingsURL.path + ".broom-backup-\(stamp)")
            var suffix = 2
            while fileManager.fileExists(atPath: url.path) {
                url = URL(fileURLWithPath: settingsURL.path + ".broom-backup-\(stamp)-\(suffix)")
                suffix += 1
            }
            try fileManager.copyItem(at: settingsURL, to: url)
            backup = url
            permissions = try fileManager.attributesOfItem(atPath: settingsURL.path)[.posixPermissions]
        } else {
            try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        // Last look before replacing the file: anything written since the review is not ours to discard.
        guard try currentSettings().text == plan.currentText else { throw Failure.changedSinceReview }
        try Data(plan.proposedText.utf8).write(to: settingsURL, options: .atomic)
        if let permissions {
            // The write succeeded; failing to restore the mode must not be reported as a failed change.
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: settingsURL.path)
        }
        return backup
    }

    // MARK: - Editing

    private func currentSettings() throws -> (text: String?, value: JSONValue) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            // A symlink whose target is missing would be replaced by a plain file, breaking the link.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: givenURL.path)) != nil { throw Failure.notWritable }
            return (nil, .object([]))
        }
        guard let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { throw Failure.unreadableSettings }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (text, .object([])) }
        guard let value = try? JSONParser.parse(text), case .object = value else { throw Failure.unreadableSettings }
        return (text, value)
    }

    /// Whether a hook runs the helper at this installer's path.
    private func isCurrentHook(_ hook: JSONValue) -> Bool {
        hook["command"] == .string(command)
    }

    /// Whether a hook runs any copy of Broom's helper: this one, a development build's, or one in an app that has since moved.
    private func isBroomHook(_ hook: JSONValue) -> Bool {
        guard case .string(let hookCommand)? = hook["command"] else { return false }
        if hookCommand == command { return true }
        // The command is nothing but a path, bare or single-quoted, whose file is named `broom-hook`.
        var path = hookCommand
        if path.count >= 2, path.hasPrefix("'"), path.hasSuffix("'") {
            path = String(path.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        } else if path.contains(" ") {
            return false
        }
        return path.hasPrefix("/") && path.hasSuffix("/broom-hook")
    }

    private var broomGroup: JSONValue {
        .object([.init(key: "hooks", value: .array([
            .object([
                .init(key: "type", value: .string("command")),
                .init(key: "command", value: .string(command)),
                .init(key: "timeout", value: .number(String(Self.timeout))),
            ]),
        ]))])
    }

    /// Makes every event run the current helper: entries left by another copy of Broom are repointed, and
    /// events with none get Broom's group appended. Other hooks are not touched.
    private func addHooks(to settings: inout JSONValue) throws {
        var hooks = settings["hooks"] ?? .object([])
        guard case .object = hooks else { throw Failure.unreadableSettings }

        for event in Self.events {
            var groups: [JSONValue] = []
            switch hooks[event] {
            case .array(let existing)?: groups = existing
            case nil: break
            default: throw Failure.unreadableSettings
            }

            var hasHelper = false
            for index in groups.indices {
                guard case .array(var entries)? = groups[index]["hooks"] else { continue }
                for entryIndex in entries.indices where isBroomHook(entries[entryIndex]) {
                    hasHelper = true
                    entries[entryIndex]["command"] = .string(command)
                }
                groups[index]["hooks"] = .array(entries)
            }
            if !hasHelper {
                groups.append(broomGroup)
            }
            if hooks[event] != .array(groups) {
                hooks[event] = .array(groups)
            }
        }
        settings["hooks"] = hooks
    }

    /// Removes every Broom helper entry, then any group, event and `hooks` object that removal left empty.
    private func removeHooks(from settings: inout JSONValue) throws {
        guard var hooks = settings["hooks"] else { return }
        guard case .object(let members) = hooks else { throw Failure.unreadableSettings }
        var removedAny = false

        for member in members {
            guard case .array(let groups) = member.value else { continue }
            var remaining: [JSONValue] = []
            for var group in groups {
                guard case .array(let entries)? = group["hooks"], entries.contains(where: isBroomHook) else {
                    remaining.append(group)
                    continue
                }
                removedAny = true
                let others = entries.filter { !isBroomHook($0) }
                if !others.isEmpty {
                    group["hooks"] = .array(others)
                    remaining.append(group)
                }
            }
            if remaining != groups {
                hooks[member.key] = remaining.isEmpty ? nil : .array(remaining)
            }
        }
        // Nothing of Broom's was there: leave the file exactly as it is, an empty `hooks` object included.
        guard removedAny else { return }
        if case .object(let left) = hooks, left.isEmpty {
            settings["hooks"] = nil
        } else {
            settings["hooks"] = hooks
        }
    }

    // MARK: - Formatting

    /// Prints `settings` the way `original` was written: its indentation, line endings and final newline.
    ///
    /// Layout the printer cannot reproduce, such as arrays written on one line, still changes; the diff shows that.
    static func text(of settings: JSONValue, formattedLike original: String?) -> String {
        guard let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return settings.text() + "\n"
        }
        let lines = original.components(separatedBy: "\n")
        let indented = lines.first { $0.hasPrefix(" ") || $0.hasPrefix("\t") }
        let unit = indented.map { String($0.prefix { $0 == " " || $0 == "\t" }) } ?? "  "
        var text = settings.text(unit: unit)
        // Checked on bytes: to `String`, "\r\n" is one character and does not end with "\n".
        if original.utf8.last == UInt8(ascii: "\n") { text += "\n" }
        if original.contains("\r\n") { text = text.replacingOccurrences(of: "\n", with: "\r\n") }
        return text
    }

    /// Quotes a path for the shell when it contains anything a shell would interpret.
    static func shellQuoted(_ path: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+")
        guard path.unicodeScalars.contains(where: { !safe.contains($0) }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
