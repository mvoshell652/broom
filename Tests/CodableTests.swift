import Foundation
import Testing
@testable import BroomCore

@Suite("Codable round trips")
struct CodableTests {
    @Test("A session survives encoding and decoding in every state", arguments: LiveState.allCases)
    func liveSession(state: LiveState) throws {
        var session = LiveSession.fixture(
            state, waitingMessage: "Allow Bash?", hasNotifiedWaiting: true,
            snoozedUntil: TestClock.at(TestClock.hour), transcriptTail: .pendingTool(name: "Bash")
        )
        session.progress = StepProgress(completed: 2, total: 5)
        session.transcriptCounts = ActivityCounts(userTurns: 9, toolCalls: 30)
        session.isInferred = true

        let decoded = try JSONDecoder().decode(LiveSession.self, from: JSONEncoder().encode(session))

        #expect(decoded == session)
    }

    @Test("A session written under the old column names still decodes")
    func oldFlagNames() throws {
        var session = LiveSession.fixture(.waiting, hasNotifiedWaiting: true)
        session.isInferred = true
        var stored = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any]
        )

        #expect(stored["inferred"] as? Bool == true)
        #expect(stored["waitingNotified"] as? Bool == true)
        #expect(stored["isInferred"] == nil)
        #expect(stored["hasNotifiedWaiting"] == nil)

        stored["inferred"] = false
        let decoded = try JSONDecoder().decode(LiveSession.self, from: JSONSerialization.data(withJSONObject: stored))

        #expect(decoded.isInferred == false)
        #expect(decoded.hasNotifiedWaiting)
    }

    @Test("A parsed digest survives encoding and decoding", arguments: Fixture.allCases)
    func digest(fixture: Fixture) throws {
        let digest = try fixture.digest

        let decoded = try JSONDecoder().decode(TranscriptDigest.self, from: JSONEncoder().encode(digest))

        #expect(decoded == digest)
    }
}
