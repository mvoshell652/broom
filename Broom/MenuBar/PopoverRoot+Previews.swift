// The previews build in debug only: the `#Preview` macro's plugin ships with Xcode, and release builds must work with
// the Command Line Tools alone.
#if DEBUG
import BroomCore
import SwiftUI

#Preview("All sections") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.everything, now: SampleData.now)
}

#Preview("All sections, dark") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.everything, now: SampleData.now)
        .preferredColorScheme(.dark)
}

#Preview("Waiting only") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.sections(SampleData.waiting), now: SampleData.now)
}

#Preview("Running only") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.sections(SampleData.running), now: SampleData.now)
}

#Preview("Running with a scheduled task") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.sections(SampleData.running), now: SampleData.now, scheduledTasks: SampleData.scheduledTasks)
}

#Preview("Done since you looked only") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.sections(SampleData.done), now: SampleData.now)
}

#Preview("Quick chats only") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.sections(SampleData.quick), now: SampleData.now)
}

#Preview("Empty") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.empty, now: SampleData.now)
}

#Preview("Empty, hooks not connected") {
    PopoverRoot(tab: .constant(.live), sections: SampleData.empty, now: SampleData.now, offersConnect: true)
}

#Preview("Inbox") {
    PopoverRoot(tab: .constant(.inbox), sections: SampleData.everything, inbox: SampleData.inbox, now: SampleData.now)
}

#Preview("Sweep deck") {
    PopoverRoot(
        tab: .constant(.inbox), sections: SampleData.everything, sweepCards: SampleData.sweepCards,
        sweepDeck: SweepDeck(cards: SampleData.sweepCards), now: SampleData.now
    )
}

#Preview("History") {
    PopoverRoot(tab: .constant(.history), sections: SampleData.everything, history: SampleData.history, now: SampleData.now)
}

#Preview("Menu bar item") {
    HStack(spacing: 24) {
        MenuBarLabel(runningCount: 0, waitingCount: 0)
        MenuBarLabel(runningCount: 2, waitingCount: 0)
        MenuBarLabel(runningCount: 2, waitingCount: 1)
        MenuBarLabel(runningCount: 0, waitingCount: 1)
    }
    .padding()
}
#endif
