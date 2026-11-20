import Foundation

/// One change the user made in the Inbox or the sweep, which can be undone for 30 days.
public struct OrganizerLogEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    /// What happened, as the list of recent changes says it: "Merged 3 chats: “RLS policies”".
    public var summary: String
    public var change: OrganizerChange
    public var date: Date

    public init(id: Int64, summary: String, change: OrganizerChange, date: Date) {
        self.id = id
        self.summary = summary
        self.change = change
        self.date = date
    }
}
