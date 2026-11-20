import BroomCore
import SwiftUI

/// The Inbox tab: chats that look like duplicates, chats left unfinished, and projects with chats quiet
/// long enough to archive. "Sweep now" goes through the same items as a deck of cards.
struct InboxView: View {
    let inbox: InboxContents
    /// The sweep's archive suggestions, one per project.
    var archives: [SweepCard] = []
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let group = inbox.duplicates.first {
                // One group at a time; dealing with it brings up the next.
                DuplicatesCard(group: group, groupCount: inbox.duplicates.count)
                    .id(group.id)
            }
            if !inbox.openLoops.isEmpty {
                SectionView(title: "Open loops", detail: "\(inbox.openLoops.count)", tint: .secondary) {
                    ForEach(inbox.openLoops) { loop in
                        OpenLoopRow(loop: loop, now: now)
                    }
                }
            }
            if !archives.isEmpty {
                SectionView(title: "Quiet for 3 months", detail: "\(archives.count)", tint: .secondary) {
                    ForEach(archives) { card in
                        if case .archive(let workstream, let chats) = card {
                            ArchiveSuggestionRow(workstream: workstream, chats: chats)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, BroomStyle.gutter)
        .padding(.bottom, BroomStyle.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
