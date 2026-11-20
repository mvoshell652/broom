import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@Suite("History")
struct HistoryTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func chat(_ id: String, _ title: String, cwd: String? = "/code/mobile", hoursAgo: Double = 1) -> IndexedChat {
        IndexedChat(id: id, title: title, cwd: cwd, lastActivityAt: now.addingTimeInterval(-hoursAgo * 3600), transcriptPath: "/tmp/\(id)")
    }

    private func item(_ change: OrganizerChange, summary: String = "stored", chats: [IndexedChat]) -> HistoryItem {
        HistoryItem(
            entry: OrganizerLogEntry(id: 1, summary: summary, change: change, date: now),
            chatsByID: Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        )
    }

    @Test("A change to several chats starts with its verb, says where, and lists the chats newest first")
    func severalChats() {
        let chats = [chat("a", "Older", hoursAgo: 5), chat("b", "Newer", hoursAgo: 1)]

        let merged = item(.merged(previousGroups: ["a": nil, "b": nil]), chats: chats)
        let apart = item(.markedDistinct(chatIDs: ["a", "b"]), chats: chats)
        let archived = item(.archived(chatIDs: ["a"]), chats: chats)

        #expect(merged.headline == "Merged 2 chats in mobile")
        #expect(merged.chats.map(\.title) == ["Newer", "Older"])
        #expect(apart.headline == "Kept 2 chats apart in mobile")
        #expect(archived.headline == "Archived 1 chat in mobile")
    }

    @Test("Chats from different projects, or gone from the index, are counted without a place")
    func noPlace() {
        let mixed = item(.merged(previousGroups: ["a": nil, "b": nil]), chats: [chat("a", "A"), chat("b", "B", cwd: "/code/web")])
        let gone = item(.archived(chatIDs: ["x", "y", "z"]), chats: [])

        #expect(mixed.headline == "Merged 2 chats")
        #expect(gone.headline == "Archived 3 chats")
        #expect(gone.chats.isEmpty)
    }

    @Test("A change to one chat names it, and older kinds keep their stored summary")
    func oneChat() {
        let closed = item(.closedLoop(chatID: "a", previouslyClosedAt: nil), chats: [chat("a", "Fix the build")])
        let untitled = item(.closedLoop(chatID: "a", previouslyClosedAt: nil), chats: [chat("a", "")])
        let filed = item(.filed(chatID: "a", previousWorkstreamID: nil), summary: "Filed “A” in api", chats: [chat("a", "A")])

        #expect(closed.headline == "Marked “Fix the build” done")
        #expect(closed.chats.isEmpty)
        #expect(untitled.headline == "Marked a chat done")
        #expect(filed.headline == "Filed “A” in api")
    }

    @Test("Changes are grouped by day, newest day first, and the days are named from today")
    func days() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let entries = [0.0, 2, 26, 75].enumerated().map { index, hours in
            HistoryItem(
                entry: OrganizerLogEntry(id: Int64(index), summary: "", change: .archived(chatIDs: []), date: now.addingTimeInterval(-hours * 3600)),
                headline: "change \(index)"
            )
        }
        let startOfToday = calendar.startOfDay(for: now)

        let days = HistoryDay.days(of: entries.reversed(), calendar: calendar)

        #expect(days.map { $0.items.map(\.headline) }.first == entries.filter { $0.date >= startOfToday }.map(\.headline))
        #expect(days.map(\.date) == days.map(\.date).sorted(by: >))
        #expect(days.first?.title(now: now, calendar: calendar) == "Today")
        #expect(days.dropFirst().first?.title(now: now, calendar: calendar) == "Yesterday")
        #expect(days.flatMap(\.items).count == 4)
    }
}
