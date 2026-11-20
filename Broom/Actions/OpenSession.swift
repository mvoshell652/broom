import AppKit
import BroomCore
import BroomShared

/// Brings a session to the user: its terminal if it is running, a resumed session in a new terminal if not.
@MainActor
struct OpenSession {
    enum Outcome: Equatable {
        /// The app hosting the session was brought to the front.
        case activated(appName: String)
        /// A terminal was started with the resume command.
        case launched(appName: String)
        /// Nothing could be opened; the resume command is on the clipboard.
        case copied
        /// The session cannot be resumed from here.
        case unavailable
    }

    /// Where resume scripts are written.
    let scriptDirectory: URL

    func open(_ session: LiveSession, preferredTerminal: TerminalApp?) async -> Outcome {
        if let pid = session.pid, StopSession.isRunning(pid) {
            if let app = Self.hostApplication(of: pid), await bringForward(app, chatOf: pid) {
                return .activated(appName: app.localizedName ?? "the terminal")
            }
            // Running somewhere Broom cannot bring forward (tmux, ssh). Starting a second copy would fork the session.
            return copyCommand(for: session)
        }

        let terminal = preferredTerminal.flatMap { $0.applicationURL == nil ? nil : $0 } ?? .terminal
        guard let applicationURL = terminal.applicationURL else { return copyCommand(for: session) }
        do {
            if terminal.runsScripts, let script = try writeScript(for: session) {
                let configuration = NSWorkspace.OpenConfiguration()
                if terminal == .ghostty {
                    configuration.arguments = ["-e", script.path]
                    configuration.createsNewApplicationInstance = true
                    try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
                } else {
                    try await NSWorkspace.shared.open([script], withApplicationAt: applicationURL, configuration: configuration)
                }
                return .launched(appName: terminal.name)
            }
            // An editor or a terminal that takes no script: open the folder there and leave the command to paste.
            if let cwd = session.cwd {
                try await NSWorkspace.shared.open(
                    [URL(fileURLWithPath: cwd)], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration()
                )
            }
        } catch {
            // Fall through to the clipboard.
        }
        return copyCommand(for: session)
    }

    /// Puts the resume command on the clipboard.
    @discardableResult
    func copyCommand(for session: LiveSession) -> Outcome {
        guard let command = ResumeCommand.command(for: session) else { return .unavailable }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        return .copied
    }

    /// Shows the session's transcript in Finder. Returns whether there was one to show.
    @discardableResult
    func revealTranscript(of session: LiveSession) -> Bool {
        guard let path = session.transcriptPath, FileManager.default.fileExists(atPath: path) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return true
    }

    /// The Claude desktop app, which hosts sessions started from its Code tab.
    static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    /// The Claude desktop app's link to one of its chats, or `nil` for an id it would refuse.
    ///
    /// The app sets `CLAUDE_CODE_HOST_SESSION_ID` to its own id for the chat (`local_…`) and accepts only that form.
    static func claudeChatLink(hostSessionID id: String) -> URL? {
        guard id.wholeMatch(of: /local_[A-Za-z0-9-]{1,64}/) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: id)]
        return components.url
    }

    /// Brings `app` to the front. Returns whether it was asked to come forward.
    ///
    /// Broom is a menu bar app and never the active app, so `NSRunningApplication.activate()` is refused under cooperative
    /// activation. Opening the app through Launch Services is what the Dock does, and it works from the background.
    ///
    /// In the Claude desktop app it opens the chat itself, by the app's own id for it.
    private func bringForward(_ app: NSRunningApplication, chatOf pid: Int32) async -> Bool {
        guard let bundleURL = app.bundleURL else { return app.activate() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            if app.bundleIdentifier == Self.claudeDesktopBundleID,
               let id = ProcessInspector.environmentValue(named: "CLAUDE_CODE_HOST_SESSION_ID", of: pid),
               let link = Self.claudeChatLink(hostSessionID: id) {
                try await NSWorkspace.shared.open([link], withApplicationAt: bundleURL, configuration: configuration)
            } else {
                try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            }
            return true
        } catch {
            return app.activate()
        }
    }

    /// The regular app that `pid` runs inside: the nearest ancestor that has a Dock presence.
    static func hostApplication(of pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = ProcessInspector.parent(of: current), parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    private func writeScript(for session: LiveSession) throws -> URL? {
        guard let script = ResumeCommand.script(for: session) else { return nil }
        try FileManager.default.createDirectory(
            at: scriptDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let url = scriptDirectory.appending(path: "\(session.id).command")
        try Data(script.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
