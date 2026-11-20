import BroomCore
import Foundation

/// `Broom --list` and `Broom --watch`: the debug window's contents on stdout, for checking the engine without a UI.
enum DebugCommand {
    /// Prints the live sessions once. With `watch`, keeps printing each session whenever its state changes.
    static func run(projectsDirectory: URL, watch: Bool) async {
        let watcher = TranscriptWatcher(projectsDirectory: projectsDirectory)
        let monitor = ProcessMonitor()
        var registry = SessionRegistry()

        for event in await watcher.scanAll() {
            registry.apply(event)
        }
        registry.tick(at: Date(), processes: await monitor.snapshot())
        var printed: [String: LiveState] = [:]
        printChanges(in: registry, since: &printed)
        if printed.isEmpty {
            print("No live sessions in \(projectsDirectory.path)")
        }
        guard watch else { return }

        let inputs = AsyncStream<Input> { continuation in
            let eventTask = Task {
                for await event in watcher.events() {
                    continuation.yield(.event(event))
                }
            }
            let tickTask = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                    continuation.yield(.tick)
                }
            }
            continuation.onTermination = { _ in
                eventTask.cancel()
                tickTask.cancel()
            }
        }
        // Both producers feed this one loop, so the registry is only touched from here.
        for await input in inputs {
            switch input {
            case .event(let event):
                registry.apply(event)
            case .tick:
                registry.tick(at: Date(), processes: await monitor.snapshot())
            }
            printChanges(in: registry, since: &printed)
        }
    }

    private enum Input: Sendable {
        case event(SessionEvent)
        case tick
    }

    private static func printChanges(in registry: SessionRegistry, since printed: inout [String: LiveState]) {
        for session in registry.sessionsByID.values.sorted(by: { $0.lastActivityAt < $1.lastActivityAt })
        where printed[session.id] != session.state && !(session.state == .ended && printed[session.id] == nil) {
            printed[session.id] = session.state
            let time = Date().formatted(date: .omitted, time: .standard)
            let state = session.state.rawValue + (session.isInferred ? "*" : "")
            let progress = session.progress.map { " \($0.completed)/\($0.total)" } ?? ""
            let pid = session.pid.map { " pid \($0)" } ?? ""
            let message = session.waitingMessage.map { " — \($0)" } ?? ""
            print("\(time)  \(state.padding(toLength: 9, withPad: " ", startingAt: 0)) \(session.id.prefix(8))  \(session.repoName ?? "-")  \"\(session.title)\"  turns \(session.userTurns) tools \(session.toolCalls)\(progress)\(pid)\(message)")
        }
        fflush(stdout)
    }
}
