import BroomCore
import SwiftUI

/// A plain table of every live session and its state, for checking the engine against real sessions.
struct DebugSessionsView: View {
    let model: LiveViewModel

    var body: some View {
        Table(model.sessions) {
            TableColumn("State") { session in
                Text(session.state.rawValue + (session.isInferred ? " (inferred)" : ""))
            }
            .width(min: 90, ideal: 130)
            TableColumn("Title") { session in
                Text(session.title.isEmpty ? "Untitled" : session.title)
                    .help(session.waitingMessage ?? session.title)
            }
            .width(min: 160, ideal: 280)
            TableColumn("Repo") { session in
                Text(session.repoName ?? "")
            }
            .width(min: 80, ideal: 120)
            TableColumn("Turns") { session in
                Text(session.userTurns, format: .number)
            }
            .width(50)
            TableColumn("Tools") { session in
                Text(session.toolCalls, format: .number)
            }
            .width(50)
            TableColumn("Progress") { session in
                if let progress = session.progress {
                    Text("\(progress.completed) of \(progress.total)")
                }
            }
            .width(70)
            TableColumn("Last activity") { session in
                Text(session.lastActivityAt, format: .relative(presentation: .numeric))
            }
            .width(min: 90, ideal: 110)
            TableColumn("PID") { session in
                if let pid = session.pid {
                    Text(pid, format: .number.grouping(.never))
                }
            }
            .width(60)
            TableColumn("Hooks") { session in
                Text(session.hasHookEvents ? "Yes" : "No")
            }
            .width(50)
        }
        .overlay {
            if model.sessions.isEmpty {
                ContentUnavailableView("No live sessions", systemImage: "moon.zzz", description: Text("Nothing has been active in the last 24 hours."))
            }
        }
        .task {
            await model.run()
        }
    }
}
