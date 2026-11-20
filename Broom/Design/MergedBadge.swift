import SwiftUI

/// "+2 merged": how many older chats sit under a merged row.
struct MergedBadge: View {
    let count: Int

    var body: some View {
        Text("+\(count) merged")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: .capsule)
            .fixedSize()
            .accessibilityLabel("^[\(count) older chat](inflect: true) merged")
    }
}
