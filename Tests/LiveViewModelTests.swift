import Foundation
import os
import Testing
@testable import Broom
@testable import BroomCore

@Suite("LiveViewModel")
@MainActor
struct LiveViewModelTests {
    private let time = OSAllocatedUnfairLock(initialState: TestClock.start)
    private let live: LiveViewModel

    init() {
        let time = time
        live = LiveViewModel(sources: [], store: nil, clock: { time.withLock { $0 } })
    }

    private func advance(to seconds: TimeInterval) {
        time.withLock { $0 = TestClock.at(seconds) }
    }

    @Test("With the popover closed, an update inside the same minute leaves the time alone")
    func sameMinuteClosed() async {
        advance(to: 10)
        await live.popoverDidClose()

        #expect(live.now == TestClock.start)
    }

    @Test("With the popover closed, the time moves when a new minute begins")
    func newMinuteClosed() async {
        advance(to: 65)
        await live.popoverDidClose()

        #expect(live.now == TestClock.at(65))
    }

    @Test("Opening the popover brings the time up to date, so ages are right when it shows")
    func opening() {
        advance(to: 10)
        live.popoverWillOpen()

        #expect(live.now == TestClock.at(10))
    }

    @Test("The time moves at once when the sections change")
    func sectionsChange() {
        advance(to: 10)
        live.seed([.fixture(.waiting)])

        #expect(live.now == TestClock.at(10))
        #expect(live.sections.waiting.count == 1)
    }
}

@Suite("LiveViewModel quiet processes")
@MainActor
struct LiveViewModelQuietProcessesTests {
    private let live = LiveViewModel(sources: [], store: nil, clock: { TestClock.at(3 * 3600) })

    @Test("A session quiet for two hours with a live process is published as left running")
    func publishesQuietProcesses() {
        live.seed([
            LiveSession(
                id: "a", title: "a", cwd: "/code/a", state: .done, startedAt: TestClock.start,
                lastActivityAt: TestClock.at(60), stateChangedAt: TestClock.at(60), userTurns: 3, toolCalls: 5, pid: 7
            ),
        ])

        #expect(live.quietProcesses.idle.map(\.id) == ["a"])
    }
}
