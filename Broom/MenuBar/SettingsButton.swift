import SwiftUI

/// The gear in the popover's header, which opens Settings.
struct SettingsButton: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass

    var body: some View {
        if #available(macOS 26, *), allowsSystemGlass {
            Button("Settings", systemImage: "gearshape", action: showSettings)
                .labelStyle(.iconOnly)
                .help("Settings")
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            // The square is part of the label, so all of it takes the click and not only the glyph.
            Button(action: showSettings) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.fill.tertiary, in: .rect(cornerRadius: BroomStyle.controlRadius))
                    .contentShape(.rect(cornerRadius: BroomStyle.controlRadius))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private func showSettings() {
        actions?.showSettings(using: openSettings)
    }
}
