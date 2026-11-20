import AppKit
import os

/// The AppKit half of `PopoverWindowObserver`: it sits in the popover's window and watches it.
final class PopoverWindowObserverView: NSView {
    var visibilityChanged: (@MainActor (Bool) -> Void)?
    private var observation: (any NSObjectProtocol)?
    private var isShown = false
    private let log = Logger(subsystem: "app.broom", category: "popover")

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil
        guard let window else { return }
        observation = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        report()
    }

    /// Makes the window `height` tall, keeping its top edge under the menu bar.
    func fit(toContentHeight height: CGFloat) {
        guard let window, height > 0, abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        log.notice("Resizing the popover from \(window.frame.height, privacy: .public) to \(height, privacy: .public)")
        window.setFrame(frame, display: true)
    }

    private func report() {
        let isVisible = window?.occlusionState.contains(.visible) ?? false
        guard isVisible != isShown else { return }
        isShown = isVisible
        log.notice("The popover is now \(isVisible ? "shown" : "hidden", privacy: .public)")
        visibilityChanged?(isVisible)
    }
}
