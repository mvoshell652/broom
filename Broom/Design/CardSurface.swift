import AppKit
import SwiftUI

/// The system's grouped-content card, with an outline when the arrow keys are on it.
struct CardSurface: ViewModifier {
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass
    var isSelected = false

    func body(content: Content) -> some View {
        surface(content.padding(12).frame(maxWidth: .infinity, alignment: .leading))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: BroomStyle.cardRadius)
                        .strokeBorder(BroomStyle.waitingText, lineWidth: 2)
                }
            }
    }
}

extension CardSurface {
    /// A glass panel with a trace of the waiting amber on macOS 26 and later; the system's control background before that.
    /// An opaque card left the glass buttons on it with nothing behind them to show.
    @ViewBuilder
    fileprivate func surface(_ content: some View) -> some View {
        if #available(macOS 26, *), allowsSystemGlass {
            content.glassEffect(.regular.tint(Color(hex: BroomStyle.waitingButton.light).opacity(0.12)), in: .rect(cornerRadius: BroomStyle.cardRadius))
        } else {
            content.background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: BroomStyle.cardRadius))
        }
    }
}

extension View {
    func cardSurface(isSelected: Bool = false) -> some View {
        modifier(CardSurface(isSelected: isSelected))
    }
}
