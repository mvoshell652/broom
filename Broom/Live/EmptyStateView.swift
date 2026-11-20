import SwiftUI

/// Shown when a tab has nothing in it.
struct EmptyStateView: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    @Environment(\.openSettings) private var openSettings
    let message: String
    /// Whether to offer installing the hooks. Off once they are installed.
    var offersConnect = false

    var body: some View {
        VStack(spacing: 12) {
            BroomGlyph()
                .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            if offersConnect {
                Button("Connect Claude Code") { actions?.showSettings(using: openSettings) }
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
