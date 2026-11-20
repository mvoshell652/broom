import BroomCore
import Foundation

/// The changes made on one day, for a section of the History tab.
struct HistoryDay: Identifiable, Equatable {
    /// The start of the day.
    let date: Date
    /// Newest first.
    let items: [HistoryItem]

    var id: Date { date }

    /// "Today", "Yesterday", or the weekday and date, as seen from `now`.
    func title(now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// `items` split by the day they were made, newest day first.
    static func days(of items: [HistoryItem], calendar: Calendar = .current) -> [HistoryDay] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { HistoryDay(date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
}
