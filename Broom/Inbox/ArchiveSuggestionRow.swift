import BroomCore
import SwiftUI

/// A project's chats that have been quiet for 90 days and were not left open, with a button that archives them.
///
/// The section above it says how long they have been quiet, so the row names only the project and the count.
struct ArchiveSuggestionRow: View {
    @Environment(WorkstreamsModel.self) private var model: WorkstreamsModel?
    let workstream: Workstream
    let chats: [IndexedChat]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(workstream.name)
                    .font(.body.weight(.medium))
                    .layoutPriority(1)
                Text("· ^[\(chats.count) chat](inflect: true)")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Archive", action: archive)
                .buttonStyle(.bordered)
                .accessibilityLabel("Archive \(chats.count) chats in \(workstream.name)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func archive() {
        Task { await model?.archive(chats, in: workstream) }
    }
}
