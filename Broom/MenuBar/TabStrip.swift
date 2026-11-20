import SwiftUI

/// The popover's tabs. Live and Inbox show how many items they hold.
///
/// Glass with a sliding selection on macOS 26 and later, the system's segmented control before that.
struct TabStrip: View {
    @Environment(\.allowsSystemGlass) private var drawsSystemControls
    @Binding var selection: PopoverTab
    let liveCount: Int
    let inboxCount: Int

    var body: some View {
        if #available(macOS 26, *), drawsSystemControls {
            GlassTabStrip(selection: $selection, title: title(of:))
        } else if drawsSystemControls {
            Picker("View", selection: $selection) {
                ForEach(PopoverTab.allCases, id: \.self) { tab in
                    Text(title(of: tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
        } else {
            // Drawing to an image cannot draw the system control, so `Broom --render` gets a plain stand-in.
            HStack(spacing: 4) {
                ForEach(PopoverTab.allCases, id: \.self) { tab in
                    Text(title(of: tab))
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(tab == selection ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: BroomStyle.buttonRadius))
                }
            }
            .padding(4)
            .background(.fill.tertiary, in: .rect(cornerRadius: BroomStyle.controlRadius))
        }
    }

    private func title(of tab: PopoverTab) -> String {
        switch tab {
        case .live: "Live · \(liveCount)"
        case .inbox: inboxCount == 0 ? "Inbox" : "Inbox · \(inboxCount)"
        case .history: "History"
        }
    }
}
