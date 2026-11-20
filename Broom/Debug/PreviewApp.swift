import AppKit
import BroomCore
import SwiftUI

/// `Broom --preview`: the popover with sample data in an ordinary window, to look at Liquid Glass without the menu bar.
///
/// The menu bar window's own glass is imitated with a glass panel over a striped backdrop, so it is close to the real
/// thing and not identical. Prints the window number, for `screencapture -l`.
struct PreviewApp: App {
    @State private var tab = PreviewApp.launchTab

    /// `--tab inbox|history` picks the tab the window opens on.
    private static var launchTab: PopoverTab {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--tab"), arguments.indices.contains(index + 1) else { return .live }
        return switch arguments[index + 1] {
        case "inbox": .inbox
        case "history": .history
        default: .live
        }
    }
    var body: some Scene {
        Window("Broom Preview", id: "preview") {
            ZStack {
                LinearGradient(colors: [.blue, .white, .gray, .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                panel
                    .padding(24)
            }
            // `--dark` shows the dark appearance whatever the system is set to.
            .preferredColorScheme(CommandLine.arguments.contains("--dark") ? .dark : nil)
            .onAppear {
                // Run from `swift run` there is no bundle, so ask for a Dock icon and focus explicitly.
                NSApplication.shared.setActivationPolicy(.regular)
                // Glass controls draw differently in a window that is not frontmost, so come forward even when launched
                // from a shell. `--background` stays behind, so the window does not take the keyboard from other work.
                if !CommandLine.arguments.contains("--background") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if let window = NSApplication.shared.windows.first(where: \.isVisible), let screen = window.screen {
                        // The frame is printed from the top-left, as `screencapture -R` takes it.
                        let frame = window.frame
                        print("window \(window.windowNumber)")
                        print("frame \(Int(frame.minX)),\(Int(screen.frame.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))")
                        fflush(stdout)
                    }
                }
            }
            .task {
                // `--cycle` steps through the tabs as a click would, to watch the switch without clicking.
                guard CommandLine.arguments.contains("--cycle") else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.5))
                    let tabs = PopoverTab.allCases
                    let next = tabs[((tabs.firstIndex(of: tab) ?? 0) + 1) % tabs.count]
                    tab = next
                }
            }
        }
        .windowResizability(.contentSize)
    }

    @ViewBuilder private var panel: some View {
        if CommandLine.arguments.contains("--search") {
            SearchView(model: Self.sampleSearch) {}
        } else {
            if CommandLine.arguments.contains("--popover-search") {
                // The popover with a search typed, which replaces its tabs with results.
                popover.environment(Self.sampleSearch)
            } else {
                popover
            }
        }
    }

    /// A search model over a few made-up chats, with a query already typed.
    private static let sampleSearch: SearchModel = {
        let store = try? ChatIndexStore()
        let chats: [(String, String, String, String)] = [
            ("1", "Search ranking v2 scoring", "api-server", "We settled on weighting title match at 0.4, recency at 0.3, popularity at 0.2 and price at 0.1."),
            ("2", "rank_score() migration", "api-server", "Updated the SQL function to use the new weights and added a tie-break on most recent update."),
            ("3", "Ranking explainer for the blog", "planning", "For readers, describe the weights as relevance first, then freshness, rather than the exact numbers."),
            ("4", "Ranking rules recap", "research", "Ranking weights and tie-breaks per the design doc."),
        ]
        for (id, title, repo, reply) in chats {
            var chat = IndexedChat(id: id, title: title, hasCustomTitle: true, cwd: "/Users/dev/code/" + repo, transcriptPath: "/tmp/" + id)
            chat.firstPrompt = "Where did we land on search ranking weights?"
            chat.lastActivityAt = SampleData.now.addingTimeInterval(-Double(id)! * 400_000)
            try? store?.save(chat, adding: [ChatTurn(role: .assistant, text: reply)], fileNumber: 0, offset: 0)
        }
        let model = SearchModel(store: store, projectsDirectory: nil, embedder: nil)
        model.query = "search ranking weights"
        return model
    }()

    @ViewBuilder private var popover: some View {
        let popover = PopoverRoot(
            tab: $tab, sections: SampleData.everything, inbox: SampleData.inbox,
            sweepCards: SampleData.sweepCards,
            sweepDeck: CommandLine.arguments.contains("--deck") ? SweepDeck(cards: SampleData.sweepCards) : nil,
            history: SampleData.history, lastSweptAt: SampleData.now.addingTimeInterval(-6 * 86_400),
            now: SampleData.now, scheduledTasks: SampleData.scheduledTasks, quietProcesses: SampleData.quietProcesses
        )
        if #available(macOS 26, *) {
            popover.glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            popover.clipShape(.rect(cornerRadius: 12))
        }
    }
}
