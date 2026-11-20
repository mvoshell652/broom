import SwiftUI

/// Styles a popover button: a system glass capsule on macOS 26 and later, a 28 pt pill before that.
struct BroomButtonModifier: ViewModifier {
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass
    let kind: BroomButtonKind

    func body(content: Content) -> some View {
        if #available(macOS 26, *), allowsSystemGlass {
            if let tint {
                content.buttonStyle(TintedGlassButtonStyle(tint: Color(hex: tint.light)))
            } else {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        } else {
            content.buttonStyle(PillButtonStyle(kind: kind))
        }
    }

    private var tint: ColorToken? {
        switch kind {
        case .primary: BroomStyle.waitingButton
        case .destructive: BroomStyle.destructiveButton
        case .secondary: nil
        }
    }
}

extension View {
    func broomButton(_ kind: BroomButtonKind) -> some View {
        modifier(BroomButtonModifier(kind: kind))
    }
}
