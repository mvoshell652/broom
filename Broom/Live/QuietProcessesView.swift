import BroomCore
import SwiftUI

/// The bottom of Live: Claude Code processes left running with nothing happening in them, and a way to stop them.
struct QuietProcessesView: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    let quiet: QuietProcesses
    let now: Date

    var body: some View {
        if !quiet.idle.isEmpty {
            SectionView(title: "Quiet, still open", detail: "\(quiet.idle.count)", tint: .secondary) {
                ForEach(quiet.idle) { session in
                    SessionRowButton(session: session) {
                        QuietRow(title: session.displayTitle, detail: "Quiet for \(TimeLabel.age(since: session.lastActivityAt, now: now))")
                    }
                }
                Button(quiet.idle.count == 1 ? "Stop…" : "Stop All…") { actions?.requestStop(quiet.idle) }
                    .broomButton(.secondary)
                    .padding(.top, 4)
            }
        }
        if !quiet.unmatched.isEmpty {
            SectionView(title: "Claude Code with no session", detail: "\(quiet.unmatched.count)", tint: .secondary) {
                ForEach(quiet.unmatched) { process in
                    QuietRow(title: process.folderName, detail: "Started \(TimeLabel.ago(since: process.startedAt, now: now))")
                }
                Button(quiet.unmatched.count == 1 ? "Stop…" : "Stop All…") { actions?.requestStop(processes: quiet.unmatched) }
                    .broomButton(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
