import BroomCore
import SwiftUI

/// The right-click menu for a session: Open, Copy resume command, Reveal transcript, Snooze, Stop.
///
/// The model is passed in: a context menu is shown outside the view tree, so it does not see the popover's environment.
struct SessionMenu: View {
    let session: LiveSession
    let actions: SessionActionsModel?

    var body: some View {
        if let actions {
            Button("Open") { actions.open(session) }
            Button("Copy Resume Command") { actions.copyResumeCommand(session) }
            Button("Reveal Transcript in Finder") { actions.revealTranscript(session) }
                .disabled(session.transcriptPath == nil)
            if session.state == .waiting {
                Divider()
                Button("Snooze for 1 Hour") { actions.snooze(session, for: .oneHour) }
                Button("Snooze Until Tomorrow") { actions.snooze(session, for: .untilTomorrow) }
            }
            if session.state == .running || session.state == .waiting {
                Divider()
                Button("Stop Session…", role: .destructive) { actions.requestStop(session) }
                    .disabled(session.pid == nil)
            }
        }
    }
}
