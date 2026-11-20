import BroomCore
import SwiftUI

/// One chat in a duplicates card under review. Clicking it resumes the chat, to check what it holds before merging.
struct DuplicateChatRow: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    let chat: IndexedChat

    var body: some View {
        Button {
            actions?.open(chat)
        } label: {
            HStack(spacing: 8) {
                Text(chat.title.isEmpty ? "Untitled chat" : chat.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let date = chat.lastActivityAt {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Resumes the chat in Claude Code")
    }
}
