import AppKit

/// The search window itself: borderless and floating, and able to take the keyboard without making Broom the active app.
final class SearchPanel: NSPanel {
    init(contentSize: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    // A borderless window refuses the keyboard unless it says otherwise, and the search field needs it.
    override var canBecomeKey: Bool { true }
}
