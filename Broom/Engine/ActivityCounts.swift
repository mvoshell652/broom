/// User turns and tool calls seen for a session by one signal source.
public struct ActivityCounts: Codable, Equatable, Sendable {
    /// Prompts the user has sent.
    public var userTurns: Int
    /// Tool calls Claude has made.
    public var toolCalls: Int

    public init(userTurns: Int = 0, toolCalls: Int = 0) {
        self.userTurns = userTurns
        self.toolCalls = toolCalls
    }
}
