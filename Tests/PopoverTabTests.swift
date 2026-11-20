import Testing
@testable import Broom

@Suite("PopoverTab")
struct PopoverTabTests {
    @Test("The tab strip leads with the Inbox, then Live, then History")
    func order() {
        #expect(PopoverTab.allCases == [.inbox, .live, .history])
    }
}
