import AppKit
import BroomCore
import SwiftUI

/// `Broom --debug`: a window listing every live session, in place of the menu bar item.
struct DebugApp: App {
    @State private var model = Launch.makeModel()

    var body: some Scene {
        Window("Broom Debug", id: "debug") {
            DebugSessionsView(model: model)
                .frame(minWidth: 820, minHeight: 320)
                .onAppear {
                    // Run from `swift run` there is no bundle, so ask for a Dock icon and focus explicitly.
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate()
                }
        }
    }
}
