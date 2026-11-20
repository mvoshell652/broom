import BroomCore
import SwiftUI

/// One session that finished since the popover was last closed.
struct DoneRow: View {
    let session: LiveSession
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(BroomStyle.done)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Finished \(TimeLabel.ago(since: session.finishedAt, now: now))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
