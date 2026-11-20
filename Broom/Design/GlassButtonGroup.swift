import SwiftUI

/// A row of buttons. On macOS 26 and later they share one glass container, so neighbouring glass blends instead of overlapping.
struct GlassButtonGroup<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass

    var body: some View {
        if #available(macOS 26, *), allowsSystemGlass {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) { content }
            }
        } else {
            HStack(spacing: 8) { content }
        }
    }
}
