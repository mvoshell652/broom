import BroomCore
import Foundation
import Observation
import SwiftUI

/// State for the Settings window: whether Claude Code is connected, and the change waiting for review.
@MainActor
@Observable
final class SettingsModel {
    /// Whether every hook event runs Broom's helper.
    private(set) var isConnected = false
    /// A change the user has asked for and not yet confirmed. Setting it shows the review sheet.
    var pendingPlan: HookInstaller.Plan?
    /// What the last action did, or why it failed.
    private(set) var statusMessage: String? {
        // The message appears inline only, so say it for VoiceOver too.
        didSet { if let statusMessage { AccessibilityNotification.Announcement(statusMessage).post() } }
    }

    let installer: HookInstaller

    init(installer: HookInstaller) {
        self.installer = installer
        refresh()
    }

    /// Re-reads the settings file.
    func refresh() {
        isConnected = installer.isInstalled()
    }

    /// Works out a change and puts it up for review. Writes nothing.
    func review(_ change: HookInstaller.Change) {
        do {
            pendingPlan = try installer.plan(change)
            statusMessage = nil
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    /// Writes the change the user just confirmed.
    func apply(_ plan: HookInstaller.Plan) {
        do {
            let backup = try installer.apply(plan)
            let action = plan.change == .connect ? "Connected." : "Disconnected."
            statusMessage = backup.map { "\(action) Backup saved as \($0.lastPathComponent)." } ?? action
        } catch {
            statusMessage = Self.message(for: error)
        }
        pendingPlan = nil
        refresh()
    }

    private static func message(for error: any Error) -> String {
        switch error as? HookInstaller.Failure {
        case .unreadableSettings: "The settings file is not valid JSON in the expected shape. Nothing was changed."
        case .changedSinceReview: "The settings file changed while you were reviewing. Nothing was written; try again."
        case .notWritable: "The settings file is read-only, or is a link to a file that does not exist. Nothing was changed."
        case .helperMissing: "Broom's hook helper is missing from this copy of the app, so connecting would not work. Nothing was changed."
        case nil: "Could not update the settings file: \(error.localizedDescription)"
        }
    }
}
