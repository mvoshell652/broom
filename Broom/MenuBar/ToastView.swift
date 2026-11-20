import SwiftUI

/// A short message about the last action, floating near the top of the popover. It is announced where it is set.
struct ToastView: View {
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass
    let message: String
    /// Undoes what the message reports. `nil` shows no Undo button.
    var undo: (() -> Void)?

    var body: some View {
        label
            .padding(.top, Self.topOffset)
            .transition(.opacity)
    }

    /// Below the search field and tabs, so it covers neither them nor the footer's button.
    private static let topOffset: CGFloat = 96

    @ViewBuilder private var label: some View {
        let content = HStack(spacing: 8) {
            Text(message)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.link)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        if #available(macOS 26, *), allowsSystemGlass {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: .capsule)
        }
    }
}
