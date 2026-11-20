import BroomCore
import SwiftUI

/// The small "CODE" tag naming where a session comes from.
struct SourceChip: View {
    let source: SessionSourceKind

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .background(.fill.tertiary, in: .rect(cornerRadius: 4))
            .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch source {
        case .claudeCode: "CODE"
        case .web: "WEB"
        case .desktop: "APP"
        }
    }

    private var accessibilityLabel: String {
        switch source {
        case .claudeCode: "Claude Code"
        case .web: "Web chat"
        case .desktop: "Desktop app"
        }
    }
}
