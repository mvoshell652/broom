import BroomCore
import SwiftUI

/// The History tab: what was changed in the last 30 days, by day, newest first.
struct HistoryView: View {
    let items: [HistoryItem]
    /// When a sweep was last finished, if ever.
    let lastSweptAt: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let lastSweptAt {
                Text("Last swept \(TimeLabel.ago(since: lastSweptAt, now: now))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            if items.isEmpty {
                Text("No changes in the last 30 days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                ForEach(HistoryDay.days(of: items)) { day in
                    SectionView(title: day.title(now: now), detail: "\(day.items.count)", tint: .secondary) {
                        ForEach(day.items) { item in
                            HistoryRow(item: item)
                        }
                    }
                }
                Text("To undo a change, right-click it. Changes can be undone for 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, BroomStyle.gutter)
        .padding(.bottom, BroomStyle.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
