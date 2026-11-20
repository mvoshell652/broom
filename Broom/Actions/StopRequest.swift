import BroomCore
import Foundation

/// A stop the user has asked for and not yet confirmed.
enum StopRequest: Equatable {
    /// Interrupt these sessions.
    case interrupt([LiveSession])
    /// These sessions were interrupted and are still running; offer `SIGTERM`.
    case force([LiveSession])
    /// Interrupt these Claude Code processes, which belong to no known session.
    case processes([ClaudeProcess])

    var sessions: [LiveSession] {
        switch self {
        case .interrupt(let sessions), .force(let sessions): sessions
        case .processes: []
        }
    }

    /// The question put to the user.
    var title: String {
        switch self {
        case .interrupt(let sessions): sessions.count == 1 ? "Stop this session?" : "Stop \(sessions.count) sessions?"
        case .force(let sessions): sessions.count == 1 ? "Still running" : "\(sessions.count) sessions are still running"
        case .processes(let processes): processes.count == 1 ? "Stop this process?" : "Stop \(processes.count) processes?"
        }
    }

    /// What will be stopped, by name, then what confirming does.
    var message: String {
        switch self {
        case .interrupt(let sessions):
            // Without hooks, which process belongs to which session is worked out from its folder.
            let consequence = sessions.allSatisfy { $0.hookProcessID != nil }
                ? "Sends an interrupt, like pressing Ctrl-C in the terminal."
                : "Sends an interrupt, like pressing Ctrl-C in the terminal. Without hooks the process is matched by folder, so check the list."
            return sessions.map(\.displayTitle).joined(separator: "\n") + "\n\n" + consequence
        case .force(let sessions):
            return sessions.map(\.displayTitle).joined(separator: "\n")
                + "\n\nThe interrupt did not end the process. Force stop asks it to quit; work in progress may be lost."
        case .processes(let processes):
            return processes.map(\.folderName).joined(separator: "\n")
                + "\n\nSends an interrupt, like pressing Ctrl-C in the terminal. Broom knows no session for these, so check the folders."
        }
    }

    var confirmLabel: String {
        switch self {
        case .interrupt(let sessions): sessions.count == 1 ? "Stop" : "Stop All"
        case .force: "Force Stop"
        case .processes(let processes): processes.count == 1 ? "Stop" : "Stop All"
        }
    }

    var cancelLabel: String {
        switch self {
        case .interrupt, .processes: "Cancel"
        case .force: "Leave Running"
        }
    }
}
