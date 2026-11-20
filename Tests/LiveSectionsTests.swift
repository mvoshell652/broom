import Foundation
import Testing
@testable import BroomCore

@Suite("LiveSections")
struct LiveSectionsTests {
    private let now = TestClock.at(1000)
    private let lastLooked = TestClock.at(500)

    private func session(
        _ id: String, _ state: LiveState, changed: TimeInterval = 600, activity: TimeInterval = 600,
        pid: Int32? = nil, snoozedUntil: Date? = nil
    ) -> LiveSession {
        LiveSession(
            id: id, state: state, startedAt: TestClock.start, lastActivityAt: TestClock.at(activity),
            stateChangedAt: TestClock.at(changed), pid: pid, snoozedUntil: snoozedUntil
        )
    }

    private func sections(_ sessions: [LiveSession], lastLooked: Date? = TestClock.at(500)) -> LiveSections {
        LiveSections(sessions: sessions, lastPopoverOpenedAt: lastLooked, now: now)
    }

    @Test("Each state lands in its section; idle and ended sessions are in none")
    func placement() {
        let result = sections([
            session("w", .waiting), session("r", .running), session("d", .done),
            session("q", .quick), session("i", .idle), session("e", .ended),
        ])

        #expect(result.waiting.map(\.id) == ["w"])
        #expect(result.running.map(\.id) == ["r"])
        #expect(result.doneSinceLooked.map(\.id) == ["d"])
        #expect(result.quickChats.map(\.id) == ["q"])
        #expect(result.liveCount == 3)
        #expect(result.agentCount == 2)
        #expect(!result.isEmpty)
    }

    @Test("Done appears only if it finished after the popover was last closed")
    func doneSinceLooked() {
        let result = sections([session("before", .done, changed: 400), session("at", .done, changed: 500), session("after", .done, changed: 501)])

        #expect(result.doneSinceLooked.map(\.id) == ["after"])
    }

    @Test("With no record of the popover closing, every done session is new")
    func neverLooked() {
        #expect(sections([session("d", .done, changed: 1)], lastLooked: nil).doneSinceLooked.count == 1)
    }

    @Test("A snoozed waiting session moves to Running until the snooze runs out")
    func snooze() {
        let snoozed = sections([session("w", .waiting, snoozedUntil: TestClock.at(1001)), session("r", .running)])
        #expect(snoozed.waiting.isEmpty)
        #expect(Set(snoozed.running.map(\.id)) == ["w", "r"])
        // Listed under Running, but the menu bar's number counts only what is actually running.
        #expect(snoozed.runningCount == 1)
        #expect(snoozed.liveCount == 2)
        #expect(snoozed.agentCount == 2)

        let expired = sections([session("w", .waiting, snoozedUntil: TestClock.at(1000))])
        #expect(expired.waiting.map(\.id) == ["w"])
        #expect(expired.running.isEmpty)
    }

    @Test("Sections list the most recent first")
    func ordering() {
        let result = sections([
            session("w-old", .waiting, changed: 600), session("w-new", .waiting, changed: 900),
            session("r-old", .running, activity: 700), session("r-new", .running, activity: 950),
            session("q-old", .quick, activity: 100), session("q-new", .quick, activity: 800),
        ])

        #expect(result.waiting.map(\.id) == ["w-new", "w-old"])
        #expect(result.running.map(\.id) == ["r-new", "r-old"])
        #expect(result.quickChats.map(\.id) == ["q-new", "q-old"])
    }

    @Test("Open counts sessions with a live process plus those running or waiting")
    func openCount() {
        let result = sections([
            session("done-open", .done, pid: 1), session("done-closed", .done),
            session("running-no-pid", .running), session("waiting", .waiting, pid: 2),
            session("quick-open", .quick, pid: 3), session("ended", .ended, pid: 4),
        ])

        #expect(result.openCount == 4)
    }

    @Test("The arrow keys move through the rows top to bottom and stop at each end")
    func keyboardOrder() {
        let result = sections([
            session("q", .quick), session("d", .done), session("r", .running), session("w", .waiting), session("i", .idle),
        ])

        #expect(result.ordered.map(\.id) == ["w", "r", "d", "q"])
        #expect(result.session(movingFrom: nil, by: 1)?.id == "w")
        #expect(result.session(movingFrom: nil, by: -1)?.id == "q")
        #expect(result.session(movingFrom: "w", by: 1)?.id == "r")
        #expect(result.session(movingFrom: "r", by: -1)?.id == "w")
        #expect(result.session(movingFrom: "w", by: -1)?.id == "w")
        #expect(result.session(movingFrom: "q", by: 1)?.id == "q")
        // A selection that has left the list starts over from the top.
        #expect(result.session(movingFrom: "gone", by: 1)?.id == "w")
        #expect(sections([]).session(movingFrom: nil, by: 1) == nil)
    }

    @Test("No sessions, or only hidden ones, is empty")
    func empty() {
        #expect(sections([]).isEmpty)
        #expect(sections([session("i", .idle), session("old", .done, changed: 100)]).isEmpty)
    }
}
