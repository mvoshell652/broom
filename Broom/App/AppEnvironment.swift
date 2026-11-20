import BroomCore
import BroomShared
import Foundation

/// Everything the running app is made of, created once and wired together.
@MainActor
final class AppEnvironment {
    let live: LiveViewModel
    let hooks: SettingsModel
    let settings: AppSettings
    let actions: SessionActionsModel
    let notifier = UserNotifier()
    let search: SearchModel
    let workstreams: WorkstreamsModel
    private let searchPanel: SearchPanelController
    private var searchHotKey: GlobalHotKey?

    init() {
        let store = Launch.makeStore()
        live = Launch.makeModel(store: store)
        hooks = SettingsModel(installer: Launch.makeInstaller())
        settings = AppSettings(store: store)
        actions = SessionActionsModel(
            live: live,
            settings: settings,
            opener: OpenSession(scriptDirectory: HookEndpoint.supportDirectory().appending(path: "resume"))
        )

        let index = Launch.makeIndexStore()
        let organizer = Launch.makeWorkstreamStore()
        search = SearchModel(store: index, projectsDirectory: Launch.projectsDirectory, organizer: organizer)
        workstreams = WorkstreamsModel(store: organizer, index: index)
        // Every pass over the transcripts can bring new chats, and the first full one is what workstreams are seeded from.
        search.didIndex = { [workstreams] in await workstreams.refresh(seeding: true) }
        searchPanel = SearchPanelController(model: search, actions: actions)
        searchHotKey = GlobalHotKey { [searchPanel] in searchPanel.toggle() }

        settings.onChange = { [live, settings] in
            live.notificationPolicy.notifiesOnWaiting = settings.notifiesOnWaiting
            live.notificationPolicy.notifiesOnDone = settings.notifiesOnDone
        }
        live.postNotification = { [notifier] content in notifier.post(content) }
        notifier.onOpen = { [actions] sessionID in actions.open(sessionID: sessionID) }
        notifier.onSnooze = { [actions] sessionID in actions.snooze(sessionID: sessionID, for: .oneHour) }
    }

    /// Loads saved settings, asks for notification permission, then runs the session pipeline until cancelled.
    func run() async {
        await settings.load()
        notifier.configure()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.live.run() }
            // Reading every transcript the first time is slow, and nothing waits on it.
            group.addTask(priority: .background) { await self.search.runIndexing() }
        }
    }
}
