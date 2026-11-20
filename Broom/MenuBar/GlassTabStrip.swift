import SwiftUI

/// The popover's tabs on macOS 26 and later: a row of buttons with one glass capsule behind the selected one, which
/// slides between tabs. The system's segmented control is not drawn as glass inside the menu bar window, so it looked flat there.
@available(macOS 26, *)
struct GlassTabStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: PopoverTab
    let title: (PopoverTab) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(title(tab))
                        .font(.callout.weight(tab == selection ? .semibold : .medium))
                        .foregroundStyle(tab == selection ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .background { selectionCapsule }
        .padding(4)
        .background(.fill.quaternary, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }

    /// The tabs are equally wide, so the capsule's place follows from the selected tab's position in the row.
    ///
    /// Only the capsule is animated. The labels and the tab's content change at once, as a segmented control's do:
    /// faded in, secondary text over glass showed as faint grey before it settled.
    private var selectionCapsule: some View {
        GeometryReader { proxy in
            let tabs = PopoverTab.allCases
            let width = proxy.size.width / CGFloat(tabs.count)
            Color.clear
                .glassEffect(.regular.interactive(), in: .capsule)
                .frame(width: width)
                .offset(x: width * CGFloat(tabs.firstIndex(of: selection) ?? 0))
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selection)
        }
    }
}
