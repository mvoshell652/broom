import SwiftUI

/// The popover's 28 pt buttons before macOS 26: a filled primary or destructive, and a bordered secondary.
struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let kind: BroomButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(kind == .secondary ? .medium : .semibold))
            .foregroundStyle(kind == .secondary ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                switch kind {
                case .primary:
                    RoundedRectangle(cornerRadius: BroomStyle.buttonRadius).fill(BroomStyle.waitingButton)
                case .destructive:
                    RoundedRectangle(cornerRadius: BroomStyle.buttonRadius).fill(BroomStyle.destructiveButton)
                case .secondary:
                    RoundedRectangle(cornerRadius: BroomStyle.buttonRadius).fill(.background)
                    RoundedRectangle(cornerRadius: BroomStyle.buttonRadius).strokeBorder(.separator)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(.rect(cornerRadius: BroomStyle.buttonRadius))
    }
}
