import AppKit
import SwiftUI

/// Reports when the window holding it is shown or hidden, and keeps that window as tall as its content.
///
/// The menu bar window is hidden, not removed, when the popover closes, so SwiftUI's `onAppear` and `onDisappear` run only
/// once. It also keeps the height of the tallest content it has shown. Neither has a SwiftUI answer, hence this view.
struct PopoverWindowObserver: NSViewRepresentable {
    /// The height the popover's content wants.
    let contentHeight: CGFloat
    /// Called with `true` when the popover is shown and `false` when it is hidden.
    let visibilityChanged: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> PopoverWindowObserverView {
        let view = PopoverWindowObserverView()
        view.visibilityChanged = visibilityChanged
        return view
    }

    func updateNSView(_ view: PopoverWindowObserverView, context: Context) {
        view.visibilityChanged = visibilityChanged
        view.fit(toContentHeight: contentHeight)
    }
}
