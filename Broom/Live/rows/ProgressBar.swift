import SwiftUI

/// The 3 pt bar under a running row. Decorative: the row's text already says "step X of Y".
struct ProgressBar: View {
    /// 0 to 1.
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(BroomStyle.runningTrack)
            .frame(height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(BroomStyle.running)
                    .scaleEffect(x: min(max(fraction, 0), 1), anchor: .leading)
            }
            .clipShape(.capsule)
            .accessibilityHidden(true)
    }
}
