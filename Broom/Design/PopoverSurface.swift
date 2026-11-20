import SwiftUI

/// What sits behind the popover's content.
///
/// On macOS 26 and later the menu bar window brings its own glass, so nothing is drawn over it. Before that, and when
/// rendering to an image where there is no window, it is an opaque surface.
struct PopoverSurface: ViewModifier {
    let isInWindow: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *), isInWindow {
            content
        } else {
            content.background(BroomStyle.popover)
        }
    }
}
