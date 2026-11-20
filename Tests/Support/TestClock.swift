import Foundation

/// Fixed times for tests. Every fixture transcript starts at `start`.
enum TestClock {
    /// 2026-11-14T10:00:00Z
    static let start = Date(timeIntervalSince1970: 1_794_650_400)

    /// `seconds` after `start`.
    static func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3600
}
