import SwiftUI

/// The bottom bar of the Inbox and History tabs: how much is indexed, and the way to the sweep.
struct IndexFooter: View {
    let indexedCount: Int
    /// Starts a sweep. `nil` hides the button.
    var sweep: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("^[\(indexedCount) chat](inflect: true) indexed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let sweep {
                    Button("Sweep now", action: sweep)
                        .broomButton(.secondary)
                }
            }
            .padding(.horizontal, BroomStyle.gutter)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
        }
    }
}
