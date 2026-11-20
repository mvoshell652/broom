import SwiftUI

/// Says what the user just changed in the Inbox or the sweep, with Undo, in whichever tab they did it.
struct ChangeToast: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: WorkstreamsModel

    var body: some View {
        ZStack {
            if let change = model.lastChange {
                ToastView(message: change.summary) {
                    Task { await model.undo(change) }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.lastChange?.id)
    }
}
