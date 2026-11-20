import SwiftUI

/// The running app's toast. It reads the message itself, so a message coming and going redraws this and not the whole popover.
struct LiveToast: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let actions: SessionActionsModel

    var body: some View {
        ZStack {
            if let toast = actions.toast {
                ToastView(message: toast)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: actions.toast)
    }
}
