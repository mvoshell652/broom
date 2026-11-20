import BroomCore
import SwiftUI

/// One session that is waiting on the user: what it asked, how long ago, and the two ways to answer.
struct WaitingCard: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    let session: LiveSession
    let now: Date
    /// Whether the arrow keys are on this card.
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SourceChip(source: session.source)
                Text(session.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let message = session.waitingMessage {
                    Text(message)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Paused \(TimeLabel.ago(since: session.stateChangedAt, now: now))")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            GlassButtonGroup {
                Button("Open chat") { actions?.open(session) }
                    .broomButton(.primary)
                Button("Snooze 1h") { actions?.snooze(session, for: .oneHour) }
                    .broomButton(.secondary)
            }
        }
        .cardSurface(isSelected: isSelected)
        // One element holding the others, so "selected" describes the card and not each button in it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(session.id)
        .contextMenu {
            SessionMenu(session: session, actions: actions)
        }
    }
}
