import BroomCore
import SwiftUI

/// One quick chat: its title and how old it is.
struct QuickChatRow: View {
    let session: LiveSession
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            // The section's 75% fade is applied to titles only: the label and ages are
            // already secondary, and fading them too would take them under 4.5:1.
            Text(session.displayTitle)
                .foregroundStyle(.primary)
                .opacity(BroomStyle.quickChatOpacity)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(TimeLabel.age(since: session.lastActivityAt, now: now))
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
