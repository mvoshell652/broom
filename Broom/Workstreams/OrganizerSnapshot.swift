import Foundation

/// Everything the Inbox and History tabs show, read in one go.
public struct OrganizerSnapshot: Equatable, Sendable {
    public var overview = WorkstreamOverview()
    public var inbox = InboxContents()
    /// The sweep's cards that are waiting.
    public var sweepCards: [SweepCard] = []
    /// Changes from the last 30 days that can be undone, newest first.
    public var history: [HistoryItem] = []
    public var lastSweptAt: Date?

    public init() {}
}
