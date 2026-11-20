import BroomCore
import Foundation
import Observation
import os

/// The user's choices: which notifications to send and which terminal to resume sessions in. Saved in Broom's database.
@MainActor
@Observable
final class AppSettings {
    /// Notify when a session starts waiting. On by default.
    var notifiesOnWaiting = true { didSet { changed("notifiesOnWaiting", notifiesOnWaiting ? "1" : "0") } }
    /// Notify when a session finishes. Off by default.
    var notifiesOnDone = false { didSet { changed("notifiesOnDone", notifiesOnDone ? "1" : "0") } }
    /// The terminal to resume sessions in. `nil` uses Terminal.
    var preferredTerminal: TerminalApp? { didSet { changed("preferredTerminal", preferredTerminal?.rawValue ?? "") } }

    /// Called after any setting changes.
    var onChange: (@MainActor () -> Void)?

    private let store: SessionStore?
    /// True only while loaded values are being assigned, so they are not written straight back.
    private var isAssigning = false
    /// Keys the user changed while `load()` was still reading, so the older stored value does not overwrite them.
    private var changedWhileLoading: Set<String>?
    private var pendingSave: Task<Void, Never>?
    private let log = Logger(subsystem: "app.broom", category: "settings")

    init(store: SessionStore?) {
        self.store = store
    }

    /// Reads the saved settings.
    func load() async {
        guard let store else { return }
        changedWhileLoading = []
        var waiting: String?, done: String?, terminal: String?
        do {
            waiting = try await store.setting("notifiesOnWaiting")
            done = try await store.setting("notifiesOnDone")
            terminal = try await store.setting("preferredTerminal")
        } catch {
            log.error("Could not load settings: \(error)")
        }
        // Assign in one synchronous step: nothing can change a setting between the reads above and here.
        let skipped = changedWhileLoading ?? []
        changedWhileLoading = nil
        isAssigning = true
        if let waiting, !skipped.contains("notifiesOnWaiting") { notifiesOnWaiting = waiting == "1" }
        if let done, !skipped.contains("notifiesOnDone") { notifiesOnDone = done == "1" }
        if let terminal, !skipped.contains("preferredTerminal") { preferredTerminal = TerminalApp(rawValue: terminal) }
        isAssigning = false
        onChange?()
    }

    /// Waits until every change made so far has been written.
    func waitForSaves() async {
        await pendingSave?.value
    }

    private func changed(_ key: String, _ value: String) {
        guard !isAssigning else { return }
        changedWhileLoading?.insert(key)
        onChange?()
        guard let store else { return }
        // Saves run off the main actor and could land out of order, so each waits for the one before it.
        let previous = pendingSave
        pendingSave = Task {
            await previous?.value
            do {
                try await store.setSetting(key, to: value)
            } catch {
                log.error("Could not save the \(key) setting: \(error)")
            }
        }
    }
}
