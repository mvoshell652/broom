import Foundation
import Testing
@testable import Broom
@testable import BroomCore

@MainActor
@Suite("AppSettings")
struct AppSettingsTests {
    @Test("After rapid changes the last value is the one saved")
    func savesInOrder() async throws {
        let store = try SessionStore()
        let settings = AppSettings(store: store)

        for index in 0..<50 { settings.notifiesOnDone = index.isMultiple(of: 2) }
        settings.notifiesOnDone = true
        await settings.waitForSaves()

        #expect(try await store.setting("notifiesOnDone") == "1")
    }

    @Test("A saved choice is loaded back")
    func loads() async throws {
        let store = try SessionStore()
        try await store.setSetting("notifiesOnWaiting", to: "0")
        let settings = AppSettings(store: store)

        await settings.load()

        #expect(settings.notifiesOnWaiting == false)
    }
}
