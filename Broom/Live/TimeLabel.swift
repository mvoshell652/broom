import Foundation

/// Short durations for rows: "22m", "1h", "2h 10m".
enum TimeLabel {
    /// A duration with up to `maximumUnits` units, or `nil` when it is under a minute.
    static func compact(_ interval: TimeInterval, maximumUnits: Int = 2) -> String? {
        guard interval >= 60 else { return nil }
        // Built by hand. Duration.UnitsFormatStyle can floor, but it skips zero units without counting them toward the
        // limit, so 1d 0h 5m comes out "1d 5m" where the rows want "1d".
        let minutes = Int(interval / 60)
        let parts = [(minutes / 1440, "d"), (minutes % 1440 / 60, "h"), (minutes % 60, "m")]
            .drop { $0.0 == 0 }
            .prefix(maximumUnits)
            .filter { $0.0 > 0 }
            .map { "\($0.0)\($0.1)" }
        return parts.joined(separator: " ")
    }

    /// "6m ago", or "just now" under a minute.
    static func ago(since date: Date, now: Date) -> String {
        compact(now.timeIntervalSince(date), maximumUnits: 1).map { "\($0) ago" } ?? "just now"
    }

    /// A row's age: "22m", or "now" under a minute.
    static func age(since date: Date, now: Date) -> String {
        compact(now.timeIntervalSince(date), maximumUnits: 1) ?? "now"
    }

    /// How long something has been going: "2h 10m", or "under 1m".
    static func elapsed(since date: Date, now: Date) -> String {
        compact(now.timeIntervalSince(date)) ?? "under 1m"
    }
}
