import BroomCore
import SwiftUI

/// One running session: title, where it is and for how long, and a progress bar when its steps are known.
struct RunningRow: View {
    let session: LiveSession
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            PulsingDot()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SourceChip(source: session.source)
                    Text(session.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress = session.progress {
                    ProgressBar(fraction: Double(progress.completed) / Double(max(progress.total, 1)))
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// `repo · step X of Y · elapsed`, with "snoozed" when the session is waiting but snoozed.
    private var meta: String {
        var parts: [String] = []
        // An untitled session already shows its folder as the title.
        if !session.title.isEmpty, let repoName = session.repoName { parts.append(repoName) }
        if let progress = session.progress { parts.append("step \(progress.completed) of \(progress.total)") }
        parts.append(TimeLabel.elapsed(since: session.startedAt, now: now))
        if session.state == .waiting { parts.append("snoozed") }
        return parts.joined(separator: " · ")
    }
}
