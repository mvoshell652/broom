import BroomCore
import SwiftUI

/// The popover as the running app shows it: live data, the actions model, the stop confirmation and the keyboard.
struct PopoverContainer: View {
    let environment: AppEnvironment
    @State private var tab = PopoverTab.live
    /// The session the arrow keys are on.
    @State private var selectedID: String?
    @FocusState private var isFocused: Bool
    /// The height the popover's content wants, which the window is kept at.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        @Bindable var actions = environment.actions
        PopoverRoot(
            tab: $tab,
            sections: environment.live.sections,
            inbox: environment.workstreams.inbox,
            sweepCards: environment.workstreams.sweepCards,
            sweepDeck: environment.workstreams.deck,
            history: environment.workstreams.history,
            lastSweptAt: environment.workstreams.lastSweptAt,
            now: environment.live.now,
            quietProcesses: environment.live.quietProcesses,
            offersConnect: !environment.hooks.isConnected,
            selectedID: selectedID
        )
        .environment(actions)
        .environment(environment.search)
        .environment(environment.workstreams)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        // Pinned to the top, so the header stays put for the moment the window is still the previous tab's height.
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            PopoverWindowObserver(contentHeight: contentHeight) { isShown in
                if isShown { popoverDidOpen() } else { popoverDidClose() }
            }
        }
        // The ring is off for the popover as a whole (below), and back on for the controls inside it.
        .focusEffectDisabled(false)
        .overlay(alignment: .top) {
            LiveToast(actions: actions)
            ChangeToast(model: environment.workstreams)
        }
        .confirmationDialog(
            actions.pendingStop?.title ?? "",
            isPresented: $actions.isConfirmingStop,
            presenting: actions.pendingStop
        ) { request in
            Button(request.confirmLabel, role: .destructive) { actions.confirmStop() }
            Button(request.cancelLabel, role: .cancel) { actions.cancelStop() }
        } message: { request in
            Text(request.message)
        }
        // Keyboard: arrows move, Return opens, Command-period stops.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.return) { openSelected() }
        .onKeyPress(KeyEquivalent("."), phases: .down) { press in
            press.modifiers.contains(.command) ? stopSelected() : .ignored
        }
    }

    // MARK: - Opening and closing

    private func popoverDidOpen() {
        environment.live.popoverWillOpen()
        environment.hooks.refresh()
        // Open loops and duplicates depend on the time and on chats indexed since the last look.
        Task { await environment.workstreams.refresh() }
        selectedID = nil
        isFocused = true
    }

    private func popoverDidClose() {
        // The next open starts on the tabs, not on an old search.
        environment.search.query = ""
        environment.actions.popoverDidClose()
        environment.workstreams.dismissToast()
        Task { await environment.live.popoverDidClose() }
    }

    // MARK: - Keyboard

    private var selectedSession: LiveSession? {
        selectedID.flatMap { id in environment.live.sections.ordered.first { $0.id == id } }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        // The arrow keys walk the Live list; the other tabs are used with the pointer.
        guard tab == .live else { return .ignored }
        guard let session = environment.live.sections.session(movingFrom: selectedID, by: offset) else { return .ignored }
        selectedID = session.id
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        // Return opens the selected row only while the list has the keyboard, not when a button inside it does.
        guard tab == .live, isFocused, let session = selectedSession else { return .ignored }
        environment.actions.open(session)
        return .handled
    }

    private func stopSelected() -> KeyPress.Result {
        guard tab == .live, let session = selectedSession, session.state == .running || session.state == .waiting else { return .ignored }
        // Asks first: the confirmation appears over the popover.
        environment.actions.requestStop(session)
        return .handled
    }
}
