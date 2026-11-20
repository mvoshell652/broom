import BroomCore
import SwiftUI

/// One chat in the search results: where it came from, its title, the passage that matched, and when it was last active.
struct SearchResultRow: View {
    let result: ChatSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("CODE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 36, height: 36)
                .background(isSelected ? AnyShapeStyle(BroomStyle.waitingButton) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Claude Code")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(result.chat.title.isEmpty ? (result.chat.repoName ?? "Untitled chat") : result.chat.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if result.mergedCount > 0 {
                        MergedBadge(count: result.mergedCount)
                    }
                    if result.isArchived {
                        Text("Archived")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: .capsule)
                            .fixedSize()
                    }
                }
                if let passage {
                    Text(passage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let date = result.chat.lastActivityAt {
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: BroomStyle.cardRadius))
        .contentShape(.rect(cornerRadius: BroomStyle.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The passage that matched, or how the chat began when it matched by meaning alone. The folder name leads either.
    private var passage: String? {
        let text = result.snippet ?? (result.chat.hasCustomTitle ? result.chat.firstPrompt : nil)
        let cleaned = text.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ") }
        return [result.chat.repoName, cleaned].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}
