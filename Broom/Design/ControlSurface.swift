import SwiftUI

/// What a header control sits on: a glass capsule on macOS 26 and later, the system fill in a rounded rectangle before that.
struct ControlSurface: ViewModifier {
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass

    func body(content: Content) -> some View {
        if #available(macOS 26, *), allowsSystemGlass {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.fill.tertiary, in: .rect(cornerRadius: BroomStyle.controlRadius))
        }
    }
}
