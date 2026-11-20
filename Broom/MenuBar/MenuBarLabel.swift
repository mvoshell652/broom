import BroomCore
import SwiftUI

/// The menu bar item's content.
struct MenuBarLabel: View {
    let runningCount: Int
    let waitingCount: Int

    var body: some View {
        Image(nsImage: MenuBarIcon.makeImage(runningCount: runningCount, hasWaiting: waitingCount > 0))
            .accessibilityLabel(MenuBarIcon.accessibilityLabel(runningCount: runningCount, waitingCount: waitingCount))
    }
}
