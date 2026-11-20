import SwiftUI

/// A coloured glass capsule, for the popover's primary and destructive buttons on macOS 26 and later.
///
/// The system's `.glassProminent` keeps a rounded rectangle on macOS whatever border shape is asked for, which left
/// these buttons a different shape from the plain glass capsules beside them.
@available(macOS 26, *)
struct TintedGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            // After the glass, so the whole capsule takes the click.
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
