import SwiftUI

/// The top of the deck: "Weekly sweep", how far through it the user is, a bar showing the same, and a way out.
struct SweepProgressHeader: View {
    @Environment(WorkstreamsModel.self) private var model: WorkstreamsModel?
    /// The card on top, counting from 1.
    let position: Int
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Weekly sweep")
                    .font(.body.weight(.semibold))
                Spacer()
                Text("\(position) of \(count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("End Sweep", systemImage: "xmark") { model?.endSweep() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Back to the Inbox list")
            }
            ProgressView(value: Double(position), total: Double(max(count, 1)))
                .tint(BroomStyle.waitingButton)
                .accessibilityLabel("Sweep progress")
                .accessibilityValue("Card \(position) of \(count)")
        }
        .padding(.horizontal, 4)
    }
}
