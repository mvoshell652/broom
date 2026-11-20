import SwiftUI

/// What the search window is drawn on: glass on macOS 26 and later, the system's window material before that.
struct SearchSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }
}
