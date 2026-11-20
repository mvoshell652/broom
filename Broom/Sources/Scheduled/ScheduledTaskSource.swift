/// Something that reports scheduled tasks. No implementation exists in v0.
public protocol ScheduledTaskSource: Sendable {
    /// Returns the full task list each time it changes.
    func tasks() -> AsyncStream<[ScheduledTask]>
}
