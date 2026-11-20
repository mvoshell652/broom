import BroomCore
import SwiftUI

/// One sweep card: what kind of suggestion it is, what it concerns, the chats involved, and what accepting does.
struct SweepCardView: View {
    let card: SweepCard
    let now: Date
    let isEditing: Bool
    @Binding var excludedChatIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tag)
                .font(.caption.weight(.bold))
                .tracking(BroomStyle.labelTracking)
                .foregroundStyle(BroomStyle.waitingLabel)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BroomStyle.waitingButton.opacity(0.12), in: .rect(cornerRadius: 4))
            Text(title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            details
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface()
        // Two more cards peeking out behind, so it reads as a deck.
        .background(alignment: .top) {
            ForEach(1..<3) { depth in
                RoundedRectangle(cornerRadius: BroomStyle.cardRadius)
                    .fill(.fill.quaternary)
                    .padding(.horizontal, CGFloat(depth) * 8)
                    .offset(y: CGFloat(depth) * -8)
            }
        }
        .padding(.top, 16)
    }

    private var tag: String {
        switch card {
        case .merge: "MERGE DUPLICATES"
        case .archive: "ARCHIVE"
        case .revisit: "REVISIT"
        }
    }

    private var title: String {
        switch card {
        case .merge(let group): "\(group.chats.count) chats about “\(group.topic)”"
        case .archive(let workstream, let chats):
            chats.count == 1 ? "1 chat in \(workstream.name), quiet for 90+ days" : "\(chats.count) chats in \(workstream.name), quiet for 90+ days"
        case .revisit(let loop): loop.chat.title.isEmpty ? "Untitled chat" : loop.chat.title
        }
    }

    private var note: String {
        switch card {
        case .merge:
            "Keeps the newest chat on top and links the others to it. Nothing gets deleted, and you can undo for 30 days."
        case .archive:
            "Archived chats leave the Inbox. Search still finds them, and one that is active again comes back. You can undo for 30 days."
        case .revisit:
            "Opens the chat in Claude Code and marks this loop done."
        }
    }

    @ViewBuilder private var details: some View {
        switch card {
        case .merge(let group):
            VStack(spacing: 4) {
                ForEach(group.chats) { chat in
                    SweepChatRow(chat: chat, isIncluded: isEditing ? inclusion(of: chat) : nil)
                }
            }
        case .archive(_, let chats):
            VStack(spacing: 4) {
                ForEach(chats.prefix(Self.listedChatCount)) { chat in
                    SweepChatRow(chat: chat, isIncluded: nil)
                }
                if chats.count > Self.listedChatCount {
                    Text("and \(chats.count - Self.listedChatCount) more")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
            }
        case .revisit(let loop):
            Text(revisitDetail(for: loop))
                .font(.callout)
        }
    }

    private func inclusion(of chat: IndexedChat) -> Binding<Bool> {
        Binding {
            !excludedChatIDs.contains(chat.id)
        } set: { isIncluded in
            if isIncluded { excludedChatIDs.remove(chat.id) } else { excludedChatIDs.insert(chat.id) }
        }
    }

    private func revisitDetail(for loop: OpenLoop) -> String {
        let how = switch loop.kind {
        case .question: "Ended on a question from Claude"
        case .deferred(let quote): "You wrote “\(quote)”"
        }
        let age = loop.chat.lastActivityAt.map { TimeLabel.ago(since: $0, now: now) }
        return [loop.workstreamName, how, age].compactMap { $0 }.joined(separator: " · ")
    }

    private static let listedChatCount = 4
}
