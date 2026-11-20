import BroomCore
import SwiftUI

/// The Live tab's sections, each hidden when empty.
struct LiveView: View {
    let sections: LiveSections
    let now: Date
    /// The session the arrow keys are on.
    var selectedID: String?
    /// Scheduled tasks to list under Running. Always empty in v0 outside previews.
    var scheduledTasks: [ScheduledTask] = []
    /// Processes left running with nothing happening in them, listed last.
    var quiet = QuietProcesses()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !sections.waiting.isEmpty {
                SectionView(title: "Waiting on you", detail: "\(sections.waiting.count)", tint: BroomStyle.waitingLabel, rowSpacing: 8) {
                    ForEach(sections.waiting) { session in
                        WaitingCard(session: session, now: now, isSelected: session.id == selectedID)
                    }
                }
            }
            if !sections.running.isEmpty || !scheduledTasks.isEmpty {
                SectionView(title: "Running", detail: "\(sections.running.count)", tint: BroomStyle.running) {
                    ForEach(sections.running) { session in
                        SessionRowButton(session: session, isSelected: session.id == selectedID) {
                            RunningRow(session: session, now: now)
                        }
                    }
                    ForEach(scheduledTasks) { task in
                        ScheduledTaskRow(task: task)
                    }
                }
            }
            if !sections.doneSinceLooked.isEmpty {
                SectionView(title: "Done since you looked", detail: "\(sections.doneSinceLooked.count)", tint: BroomStyle.done) {
                    ForEach(sections.doneSinceLooked) { session in
                        SessionRowButton(session: session, isSelected: session.id == selectedID) {
                            DoneRow(session: session, now: now)
                        }
                    }
                }
            }
            if !sections.quickChats.isEmpty {
                SectionView(title: "Quick chats", detail: "fade after 24h", tint: .secondary) {
                    ForEach(sections.quickChats) { session in
                        SessionRowButton(session: session, isSelected: session.id == selectedID) {
                            QuickChatRow(session: session, now: now)
                        }
                    }
                }
            }
            QuietProcessesView(quiet: quiet, now: now)
        }
        .padding(.horizontal, BroomStyle.gutter)
        .padding(.bottom, BroomStyle.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
