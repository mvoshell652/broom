import AppKit
import SwiftUI

/// Shows and hides the search window. AppKit is used because SwiftUI has no floating panel that takes the keyboard
/// without activating the app, which is what a search-from-anywhere window needs.
@MainActor
final class SearchPanelController: NSObject, NSWindowDelegate {
    private let model: SearchModel
    private let actions: SessionActionsModel
    private var panel: SearchPanel?

    init(model: SearchModel, actions: SessionActionsModel) {
        self.model = model
        self.actions = actions
    }

    /// Shows the window, or hides it if it is already showing.
    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        model.willPresent()
        if let screen = NSScreen.main {
            // A little above the middle, where Spotlight sits.
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.minY + (frame.height - panel.frame.height) * 0.62
            ))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Clicking elsewhere dismisses the window, as it does Spotlight.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel(contentSize: SearchView.size)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: SearchView(model: model) { [weak self] in self?.hide() }
                .environment(actions)
        )
        return panel
    }
}
