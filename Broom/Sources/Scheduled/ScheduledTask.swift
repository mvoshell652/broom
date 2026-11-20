import Foundation

/// A scheduled Claude task. v0 only renders this in previews.
public struct ScheduledTask: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var nextRunAt: Date?

    public init(id: String, title: String, nextRunAt: Date? = nil) {
        self.id = id
        self.title = title
        self.nextRunAt = nextRunAt
    }
}
