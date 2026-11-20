import BroomCore
import SwiftUI

/// A scheduled task. Nothing produces these in v0; the row exists for previews only.
struct ScheduledTaskRow: View {
    let task: ScheduledTask

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Group {
                    if let nextRunAt = task.nextRunAt {
                        Text("Scheduled task · next run \(nextRunAt, format: .dateTime.weekday(.abbreviated).hour().minute())")
                    } else {
                        Text("Scheduled task")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
