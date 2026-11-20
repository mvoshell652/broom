import BroomCore
import SwiftUI

/// Makes a row open its session when clicked and gives it the row menu.
struct SessionRowButton<Content: View>: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    let session: LiveSession
    /// Whether the arrow keys are on this row.
    var isSelected = false
    @ViewBuilder let content: Content

    var body: some View {
        Button {
            actions?.open(session)
        } label: {
            content
                .contentShape(.rect(cornerRadius: BroomStyle.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the session")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // An outline, not a fill: a fill light enough to keep the text readable is too faint to see.
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: BroomStyle.controlRadius)
                    .strokeBorder(BroomStyle.running, lineWidth: 2)
            }
        }
        .contextMenu {
            SessionMenu(session: session, actions: actions)
        }
        .id(session.id)
    }
}
