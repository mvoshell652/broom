import BroomCore
import SwiftUI

/// The menu bar app.
struct BroomApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            PopoverContainer(environment: environment)
        } label: {
            MenuBarLabel(
                runningCount: environment.live.sections.runningCount,
                waitingCount: environment.live.sections.waiting.count
            )
            .task { await environment.run() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: environment.hooks, settings: environment.settings, search: environment.search)
        }
    }
}
