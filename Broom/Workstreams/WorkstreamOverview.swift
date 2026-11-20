/// Every indexed chat, sorted into its workstream or left unsorted.
public struct WorkstreamOverview: Equatable, Sendable {
    /// Every workstream, the most recently active first. One with no chats comes last.
    public var groups: [WorkstreamGroup]
    /// Chats in no workstream, merged ones stacked, most recently active first.
    public var unsorted: [ChatStack]

    public init(groups: [WorkstreamGroup] = [], unsorted: [ChatStack] = []) {
        self.groups = groups
        self.unsorted = unsorted
    }
}
