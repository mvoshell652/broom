import BroomCore
import BroomShared
import Foundation
import os

/// Process entry point: the menu bar app, or a debug command when asked for on the command line.
@main
enum Launch {
    /// The transcripts to watch. `BROOM_PROJECTS_DIR` points Broom at a test folder instead of the real one.
    static var projectsDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["BROOM_PROJECTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return ClaudePaths.projectsDirectory(environment: environment)
    }

    /// The database to use. `BROOM_DATABASE` overrides the path; the value `:memory:` keeps nothing on disk.
    static func makeStore() -> SessionStore? {
        do {
            switch ProcessInfo.processInfo.environment["BROOM_DATABASE"] {
            case ":memory:": return try SessionStore()
            case let path? where !path.isEmpty: return try SessionStore(url: URL(fileURLWithPath: path))
            default: return try SessionStore(url: HookEndpoint.supportDirectory().appending(path: "broom.sqlite"))
            }
        } catch {
            Logger(subsystem: "app.broom", category: "launch").error("Could not open the database, running without it: \(error)")
            return nil
        }
    }

    /// The chat index, or `nil` if it cannot be opened. `BROOM_INDEX` overrides its path (`:memory:` keeps nothing on disk).
    static func makeIndexStore() -> ChatIndexStore? {
        do {
            switch ProcessInfo.processInfo.environment["BROOM_INDEX"] {
            case ":memory:": return try ChatIndexStore()
            case let path? where !path.isEmpty: return try ChatIndexStore(url: URL(fileURLWithPath: path))
            default: return try ChatIndexStore(url: HookEndpoint.supportDirectory().appending(path: "index.sqlite"))
            }
        } catch {
            Logger(subsystem: "app.broom", category: "launch").error("Could not open the chat index, search is off: \(error)")
            return nil
        }
    }

    /// The user's workstreams, or `nil` if the file cannot be opened. `BROOM_WORKSTREAMS` overrides its path (`:memory:` keeps nothing on disk).
    static func makeWorkstreamStore() -> WorkstreamStore? {
        do {
            switch ProcessInfo.processInfo.environment["BROOM_WORKSTREAMS"] {
            case ":memory:": return try WorkstreamStore()
            case let path? where !path.isEmpty: return try WorkstreamStore(url: URL(fileURLWithPath: path))
            default: return try WorkstreamStore(url: HookEndpoint.supportDirectory().appending(path: "workstreams.sqlite"))
            }
        } catch {
            Logger(subsystem: "app.broom", category: "launch").error("Could not open the workstreams, the tab is empty: \(error)")
            return nil
        }
    }

    /// The bearer token for hook events, or `nil` if its file cannot be read or created.
    static func hookToken() -> String? {
        do {
            return try HookToken.loadOrCreate(at: HookEndpoint.tokenFile())
        } catch {
            Logger(subsystem: "app.broom", category: "launch").error("Could not prepare the hook token, hooks are off: \(error)")
            return nil
        }
    }

    @MainActor
    static func makeModel(store: SessionStore? = makeStore()) -> LiveViewModel {
        let watcher = TranscriptWatcher(projectsDirectory: projectsDirectory)
        var sources: [any SessionSource] = [watcher]
        if let token = hookToken() {
            sources.append(HookServer(port: HookEndpoint.port(), token: token, record: { payload, date in
                try? await store?.recordHookEvent(payload, receivedAt: date)
            }))
        }
        let model = LiveViewModel(sources: sources, store: store)
        model.registerTranscript = { sessionID, path in
            await watcher.register(sessionID: sessionID, transcriptPath: path)
        }
        return model
    }

    /// Where `broom-hook` is: in `Contents/Helpers` of the app bundle, or next to the executable in a development build.
    static var helperPath: String {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let folder = executable.deletingLastPathComponent()
        let bundled = folder.deletingLastPathComponent().appending(path: "Helpers/broom-hook")
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled.path : folder.appending(path: "broom-hook").path
    }

    /// The installer for the user's settings file. `BROOM_SETTINGS_FILE` points it at a copy, for testing.
    static func makeInstaller() -> HookInstaller {
        let environment = ProcessInfo.processInfo.environment
        let settings = environment["BROOM_SETTINGS_FILE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? ClaudePaths.settingsFile(environment: environment)
        return HookInstaller(settingsURL: settings, helperPath: helperPath)
    }

    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--list") || arguments.contains("--watch") {
            await DebugCommand.run(projectsDirectory: projectsDirectory, watch: arguments.contains("--watch"))
        } else if let index = arguments.firstIndex(of: "--render"), arguments.indices.contains(index + 1) {
            try RenderCommand.run(outputDirectory: URL(fileURLWithPath: arguments[index + 1]))
        } else if arguments.contains("--hooks") {
            exit(HooksCommand.run(arguments: arguments, helperPath: helperPath))
        } else if arguments.contains("--debug") {
            DebugApp.main()
        } else if arguments.contains("--preview") {
            PreviewApp.main()
        } else {
            BroomApp.main()
        }
    }
}
