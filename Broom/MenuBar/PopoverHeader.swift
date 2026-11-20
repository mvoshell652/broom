import SwiftUI

/// The top of the popover: where search will go, the Settings button and the tabs.
struct PopoverHeader: View {
    @Environment(\.allowsSystemGlass) private var allowsSystemGlass
    @Binding var tab: PopoverTab
    let liveCount: Int
    let inboxCount: Int
    /// Off while a search is typed: the results take the tabs' place.
    var showsTabs = true

    var body: some View {
        VStack(spacing: 8) {
            searchRow
            if showsTabs {
                TabStrip(selection: $tab, liveCount: liveCount, inboxCount: inboxCount)
            }
        }
        .padding(EdgeInsets(top: BroomStyle.gutter, leading: BroomStyle.gutter, bottom: 12, trailing: BroomStyle.gutter))
    }

    /// On macOS 26 and later both controls are glass, so they share a container and blend where they meet.
    @ViewBuilder private var searchRow: some View {
        let row = HStack(spacing: 8) {
            PopoverSearchField()
            SettingsButton()
        }
        if #available(macOS 26, *), allowsSystemGlass {
            GlassEffectContainer(spacing: 8) { row }
        } else {
            row
        }
    }
}
