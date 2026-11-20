/// How many of a session's todo or task items are complete.
///
/// The spec calls this `Progress`; it is renamed so it does not collide with `Foundation.Progress`.
public struct StepProgress: Codable, Equatable, Sendable {
    /// Items marked complete.
    public var completed: Int
    /// All items, complete or not.
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}
