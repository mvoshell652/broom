import Foundation
import Testing
@testable import BroomCore

@Suite("QuickChatRule")
struct QuickChatRuleTests {
    @Test("userTurns ≤ 2, no tool calls and under 10 minutes is a quick chat", arguments: [
        (userTurns: 0, toolCalls: 0, seconds: 0.0, expected: true),
        (userTurns: 2, toolCalls: 0, seconds: 599.0, expected: true),
        (userTurns: 3, toolCalls: 0, seconds: 30.0, expected: false),
        (userTurns: 1, toolCalls: 1, seconds: 30.0, expected: false),
        (userTurns: 1, toolCalls: 0, seconds: 600.0, expected: false),
    ])
    func rule(userTurns: Int, toolCalls: Int, seconds: TimeInterval, expected: Bool) {
        let matches = QuickChatRule.matches(
            userTurns: userTurns,
            toolCalls: toolCalls,
            startedAt: TestClock.start,
            lastActivityAt: TestClock.at(seconds)
        )

        #expect(matches == expected)
    }
}
