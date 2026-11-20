import BroomCore
import SwiftUI

/// A chat left unfinished: a circle that marks it done, its title, and how it was left.
struct OpenLoopRow: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    @Environment(WorkstreamsModel.self) private var model: WorkstreamsModel?
    let loop: OpenLoop
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button("Mark as Done", systemImage: "circle", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(BroomStyle.waitingText)
                .help("Mark as done")
            Button {
                actions?.open(loop.chat)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loop.chat.title.isEmpty ? "Untitled chat" : loop.chat.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Resumes the chat in Claude Code")
        }
        .padding(.vertical, 4)
    }

    /// "api-server · ended on a question · 2d"
    private var detail: String {
        let how = switch loop.kind {
        case .question: "ended on a question"
        case .deferred(let quote): "“\(quote)”"
        }
        let age = loop.chat.lastActivityAt.map { TimeLabel.age(since: $0, now: now) }
        return [loop.workstreamName, how, age].compactMap { $0 }.joined(separator: " · ")
    }

    private func close() {
        Task { await model?.close(loop) }
    }
}
