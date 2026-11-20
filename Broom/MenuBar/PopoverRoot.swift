import BroomCore
import SwiftUI

/// The menu bar popover: search, tabs, the selected tab's content and the footer.
///
/// What its controls do comes from a `SessionActionsModel` in the environment; without one, as in previews, they do nothing.
struct PopoverRoot: View {
    @Environment(SearchModel.self) private var search: SearchModel?
    @Environment(WorkstreamsModel.self) private var organizer: WorkstreamsModel?
    @Binding var tab: PopoverTab
    let sections: LiveSections
    var inbox = InboxContents()
    /// The sweep's cards that are waiting.
    var sweepCards: [SweepCard] = []
    /// The sweep in progress, if any.
    var sweepDeck: SweepDeck?
    var history: [HistoryItem] = []
    var lastSweptAt: Date?
    let now: Date
    var scheduledTasks: [ScheduledTask] = []
    /// Processes left running with nothing happening in them, for the bottom of Live.
    var quietProcesses = QuietProcesses()
    /// Whether the empty Live tab offers to install the hooks.
    var offersConnect = false
    /// A short message to draw over the popover. The running app overlays its own instead.
    var toast: String?
    /// The session the arrow keys are on.
    var selectedID: String?
    /// Whether the content scrolls when it outgrows the popover. Off only for rendering to an image, where scroll views draw nothing.
    var scrolls = true

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(tab: $tab, liveCount: sections.liveCount, inboxCount: inbox.count + archiveCards.count, showsTabs: !isSearching)

            if let search, isSearching {
                // The results take the place of the tabs for as long as something is typed.
                ScrollViewReader { proxy in
                    ScrollView {
                        SearchResultsList(model: search)
                    }
                    .onChange(of: search.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity, alignment: .top)
                Divider()
                SearchFooter(resultCount: search.results.count, indexedCount: search.indexedCount, isIndexing: search.isIndexing)
            } else {
                tabContent
                    .frame(maxHeight: scrolls ? .infinity : nil, alignment: .top)
                if tab == .live {
                    FooterView(openCount: sections.openCount, agentCount: sections.agentCount, scheduledCount: scheduledTasks.count)
                } else {
                    IndexFooter(indexedCount: search?.indexedCount ?? 0, sweep: sweepAction)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                ToastView(message: toast)
            }
        }
        .frame(width: BroomStyle.popoverWidth)
        // One height for every tab, so switching tabs never resizes the window: the content sits at the top
        // and the footer at the bottom.
        .frame(height: scrolls ? BroomStyle.popoverHeight : nil, alignment: .top)
        .modifier(PopoverSurface(isInWindow: scrolls))
        .environment(\.allowsSystemGlass, scrolls)
    }

    /// "Sweep now": goes through the Inbox as a deck of cards. `nil` while a deck is showing, on History, and when
    /// nothing is waiting.
    private var sweepAction: (() -> Void)? {
        guard tab != .history, sweepDeck == nil, !sweepCards.isEmpty else { return nil }
        return {
            organizer?.startSweep()
            tab = .inbox
        }
    }

    /// The sweep's archive suggestions, which the Inbox lists after its own sections.
    private var archiveCards: [SweepCard] {
        sweepCards.filter { $0.kind == .archive }
    }

    private var isSearching: Bool {
        !(search?.query.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    @ViewBuilder private var tabContent: some View {
        if let emptyMessage {
            EmptyStateView(message: emptyMessage, offersConnect: tab == .live && offersConnect)
                .frame(maxHeight: scrolls ? .infinity : nil)
        } else if scrolls {
            // As tall as its content up to the room the popover has, then it scrolls.
            ScrollViewReader { proxy in
                ScrollView {
                    content
                }
                .onChange(of: selectedID) { _, id in
                    // Keep the row the arrow keys moved to in view.
                    if let id { proxy.scrollTo(id) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .live: LiveView(sections: sections, now: now, selectedID: selectedID, scheduledTasks: scheduledTasks, quiet: quietProcesses)
        case .inbox:
            if let sweepDeck, let card = sweepDeck.current {
                SweepDeckView(deck: sweepDeck, card: card, now: now)
            } else {
                InboxView(inbox: inbox, archives: archiveCards, now: now)
            }
        case .history: HistoryView(items: history, lastSweptAt: lastSweptAt, now: now)
        }
    }

    /// What to say when the selected tab has nothing to show, or `nil` when it has.
    private var emptyMessage: String? {
        switch tab {
        case .live: sections.isEmpty && scheduledTasks.isEmpty && quietProcesses.isEmpty ? "All quiet. Nothing running." : nil
        case .inbox: inbox.isEmpty && archiveCards.isEmpty && sweepDeck == nil ? "Nothing to tidy." : nil
        case .history: nil
        }
    }
}
