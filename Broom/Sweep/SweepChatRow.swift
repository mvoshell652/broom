import BroomCore
import SwiftUI

/// A chat listed on a sweep card: its title and when it was last active, with a checkbox while a merge is being edited.
struct SweepChatRow: View {
    let chat: IndexedChat
    /// Whether the chat stays in the merge. `nil` when the card is not being edited, which shows no checkbox.
    let isIncluded: Binding<Bool>?

    var body: some View {
        HStack(spacing: 8) {
            if let isIncluded {
                Toggle(isOn: isIncluded) { label }
                    .toggleStyle(.checkbox)
            } else {
                label
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: BroomStyle.controlRadius))
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(chat.title.isEmpty ? "Untitled chat" : chat.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let date = chat.lastActivityAt {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
