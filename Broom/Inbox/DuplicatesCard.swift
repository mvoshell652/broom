import BroomCore
import SwiftUI

/// The Inbox's card for one group of possible duplicates: what they are about, then merge them or say they differ.
struct DuplicatesCard: View {
    @Environment(WorkstreamsModel.self) private var model: WorkstreamsModel?
    let group: DuplicateGroup
    /// How many groups are waiting, this one included.
    let groupCount: Int
    /// Whether the chats are listed, which is the "review" in "Review & merge".
    @State private var isReviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(groupCount > 1 ? "POSSIBLE DUPLICATES · \(groupCount)" : "POSSIBLE DUPLICATES")
                .font(.subheadline.weight(.semibold))
                .tracking(BroomStyle.labelTracking)
                .foregroundStyle(BroomStyle.waitingLabel)
                .accessibilityAddTraits(.isHeader)
            summary
                .fixedSize(horizontal: false, vertical: true)
            if isReviewing {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.chats) { chat in
                        DuplicateChatRow(chat: chat)
                    }
                }
            }
            HStack(spacing: 8) {
                if isReviewing {
                    Button("Merge \(group.chats.count) Chats", action: merge)
                        .broomButton(.primary)
                } else {
                    Button("Review & merge") { isReviewing = true }
                        .broomButton(.primary)
                }
                Button("Not the same", action: markDistinct)
                    .broomButton(.secondary)
            }
            .padding(.top, 4)
        }
        .cardSurface()
    }

    @ViewBuilder private var summary: some View {
        if let since = group.since {
            Text("You've started **\(group.chats.count) chats** about “\(group.topic)” since \(since, format: .dateTime.month(.abbreviated).day()).")
        } else {
            Text("You've started **\(group.chats.count) chats** about “\(group.topic)”.")
        }
    }

    private func merge() {
        Task { await model?.merge(group.chats) }
    }

    private func markDistinct() {
        Task { await model?.markDistinct(group) }
    }
}
