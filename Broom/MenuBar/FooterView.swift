import SwiftUI

/// The popover's bottom bar: totals on the left, Stop all on the right.
struct FooterView: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    let openCount: Int
    let agentCount: Int
    /// Scheduled tasks waiting to run. Always zero in v0 outside previews.
    var scheduledCount = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Group {
                    if scheduledCount > 0 {
                        Text("\(openCount) open · ^[\(agentCount) agent](inflect: true) · \(scheduledCount) scheduled")
                    } else {
                        Text("\(openCount) open · ^[\(agentCount) agent](inflect: true)")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Stop all agents") { actions?.requestStopAll() }
                    .broomButton(.secondary)
                    .disabled(agentCount == 0)
            }
            .padding(.horizontal, BroomStyle.gutter)
            .padding(.vertical, 8)
        }
    }
}
