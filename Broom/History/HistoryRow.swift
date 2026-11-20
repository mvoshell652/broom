import BroomCore
import SwiftUI

/// One change in History: what was done and when, opening to the chats it touched.
///
/// Undo is in the row's menu, and shows on the row while the pointer is over it. The toast offers it right after the
/// change, which is when it is most wanted.
struct HistoryRow: View {
    @Environment(WorkstreamsModel.self) private var model: WorkstreamsModel?
    let item: HistoryItem
    @State private var isExpanded = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                headline
                Spacer(minLength: 8)
                if isHovering {
                    Button("Undo", action: undo)
                        .buttonStyle(.link)
                        .accessibilityHidden(true)
                }
                Text(item.date, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.chats) { chat in
                        Text(chat.title.isEmpty ? "Untitled chat" : chat.title)
                            .lineLimit(1)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Undo", action: undo)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", undo)
    }

    @ViewBuilder private var headline: some View {
        if item.chats.isEmpty {
            // The chevron's space is kept, so every headline starts at the same edge.
            Label {
                headlineText
            } icon: {
                chevron.hidden()
            }
            .font(.callout)
        } else {
            Button {
                isExpanded.toggle()
            } label: {
                Label {
                    headlineText
                } icon: {
                    chevron
                }
                .font(.callout)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        }
    }

    private var headlineText: some View {
        Text(item.headline)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .foregroundStyle(.secondary)
    }

    private func undo() {
        Task { await model?.undo(item.entry) }
    }
}
