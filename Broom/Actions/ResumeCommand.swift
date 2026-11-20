import BroomCore
import Foundation

/// Builds the command that resumes a session in a terminal.
enum ResumeCommand {
    /// `cd <folder> && claude --resume <id>`, or `nil` if the id is not a Claude Code session id.
    static func command(for session: LiveSession) -> String? {
        // The id goes into a shell command, so accept nothing but a UUID.
        guard UUID(uuidString: session.id) != nil else { return nil }
        let resume = "claude --resume \(session.id)"
        guard let cwd = session.cwd, !cwd.isEmpty else { return resume }
        // `--` so a folder name that starts with a dash is not read as an option.
        return "cd -- \(quoted(cwd)) && \(resume)"
    }

    /// A script a terminal can run to resume the session. It starts a login shell so `claude` is found on the user's PATH.
    static func script(for session: LiveSession) -> String? {
        guard let command = command(for: session) else { return nil }
        return "#!/bin/zsh\nexec /bin/zsh -lic \(quoted(command))\n"
    }

    /// Single-quotes `text` for the shell.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
