import BroomCore
import SwiftUI

/// The top card of the deck with its three buttons: skip it, edit what it would do, or do it.
///
/// The arrow keys and E work as the buttons do.
struct SweepCardPanel: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    @Environment(WorkstreamsModel.self) private var model: WorkstreamsModel?
    let card: SweepCard
    let now: Date
    @State private var isEditing = false
    /// Chats the user took out of a merge while editing.
    @State private var excludedChatIDs: Set<String> = []
    /// Set while the change is being saved, so a second press cannot act on the same card twice.
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 16) {
            SweepCardView(
                card: card, now: now, isEditing: isEditing, excludedChatIDs: $excludedChatIDs
            )
            HStack(spacing: 8) {
                Button(action: skip) {
                    Text("← Skip").frame(maxWidth: .infinity)
                }
                .broomButton(.secondary)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Skip until next week")
                Button {
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "Done" : "Edit").frame(maxWidth: .infinity)
                }
                .broomButton(.secondary)
                .keyboardShortcut("e", modifiers: [])
                .disabled(!canEdit)
                Button(action: accept) {
                    Text("\(actionName) →").frame(maxWidth: .infinity)
                }
                .broomButton(.primary)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!canAccept)
                .accessibilityLabel(actionName)
            }
            .disabled(isWorking)
        }
    }

    private var actionName: String {
        switch card {
        case .merge: "Merge"
        case .archive: "Archive"
        case .revisit: "Open"
        }
    }

    /// Merges can drop chats; archiving and revisiting have nothing to adjust.
    private var canEdit: Bool {
        switch card {
        case .merge: true
        case .archive, .revisit: false
        }
    }

    private var canAccept: Bool {
        if case .merge(let group) = card { return group.chats.count - excludedChatIDs.count > 1 }
        return true
    }

    private func skip() {
        isWorking = true
        Task { await model?.skipCurrentCard() }
    }

    private func accept() {
        isWorking = true
        Task {
            switch card {
            case .merge(let group):
                await model?.merge(group.chats.filter { !excludedChatIDs.contains($0.id) })
            case .archive(let workstream, let chats):
                await model?.archive(chats, in: workstream)
            case .revisit(let loop):
                // Going back to it is dealing with it; the loop returns if the chat ends open again.
                await model?.close(loop)
                actions?.open(loop.chat)
            }
            await model?.advance()
        }
    }
}
