import SwiftUI

/// The running indicator: a blue dot with a ring that pulses every 1.6 s, static under Reduce Motion.
struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        Circle()
            .fill(BroomStyle.running)
            .frame(width: 8, height: 8)
            .background {
                if !reduceMotion {
                    Circle()
                        .stroke(BroomStyle.running, lineWidth: 2)
                        .scaleEffect(isExpanded ? 2.3 : 1)
                        .opacity(isExpanded ? 0 : 0.45)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: isExpanded)
                        .onAppear { isExpanded = true }
                }
            }
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}
