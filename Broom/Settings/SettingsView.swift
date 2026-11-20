import SwiftUI

/// The Settings window. In this build it holds the Claude Code connection only.
struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Bindable var settings: AppSettings
    let search: SearchModel
    // Filled in onAppear: reading the login item status is a synchronous system call.
    @State private var opensAtLogin = false
    @State private var loginItemError: String?
    // Filled in onAppear: each lookup asks LaunchServices about every terminal app.
    @State private var terminals: [TerminalApp] = []

    var body: some View {
        Form {
            Section("Claude Code") {
                LabeledContent("Hooks") {
                    Label(
                        model.isConnected ? "Connected" : "Not connected",
                        systemImage: model.isConnected ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(model.isConnected ? AnyShapeStyle(BroomStyle.doneOnGray) : AnyShapeStyle(.secondary))
                }
                LabeledContent("Settings file") {
                    Text(model.installer.settingsURL.path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if model.isConnected {
                        Button("Disconnect…") { model.review(.disconnect) }
                    } else {
                        Button("Connect Claude Code…") { model.review(.connect) }
                            .buttonStyle(.borderedProminent)
                    }
                    if let statusMessage = model.statusMessage {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("General") {
                Toggle("Open Broom at login", isOn: $opensAtLogin)
                    .disabled(!LoginItem.isAvailable)
                    .onChange(of: opensAtLogin) { _, enabled in
                        setOpensAtLogin(enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Notifications") {
                Toggle("When a session is waiting on you", isOn: $settings.notifiesOnWaiting)
                Toggle("When a session finishes", isOn: $settings.notifiesOnDone)
                if !UserNotifier.isAvailable {
                    Text("Notifications and opening at login need Broom to run as an app, not from `swift run`.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            SearchIndexSection(search: search)

            Section("Opening sessions") {
                Picker("Resume in", selection: $settings.preferredTerminal) {
                    Text("Terminal").tag(TerminalApp?.none)
                    ForEach(pickerTerminals) { app in
                        Text(app.name).tag(TerminalApp?.some(app))
                    }
                }
                Text("A session that is still running opens in the app it is running in. This choice is for sessions that have ended.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            model.refresh()
            terminals = TerminalApp.installed.filter { $0 != .terminal }
            // The user may have changed the login item in System Settings since this window was last shown.
            opensAtLogin = LoginItem.isEnabled
        }
        .sheet(item: $model.pendingPlan) { plan in
            HookChangeSheet(plan: plan, model: model)
        }
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = LoginItem.needsApproval
                ? "Allow Broom under Login Items in System Settings to finish turning this on."
                : nil
            if LoginItem.needsApproval { LoginItem.openSystemSettings() }
        } catch {
            loginItemError = "Could not change the login item: \(error.localizedDescription)"
        }
        // The message appears inline only, so say it for VoiceOver too.
        if let loginItemError { AccessibilityNotification.Announcement(loginItemError).post() }
        // Show what the system actually has, which can differ from what was asked for.
        opensAtLogin = LoginItem.isEnabled
    }

    /// The installed terminals, plus the saved choice while the list is still empty so the picker never shows a selection it has no row for.
    private var pickerTerminals: [TerminalApp] {
        if let saved = settings.preferredTerminal, saved != .terminal, !terminals.contains(saved) {
            return terminals + [saved]
        }
        return terminals
    }

    private var explanation: String {
        model.isConnected
            ? "Claude Code tells Broom the moment a session starts, needs you, or finishes."
            : "Without hooks, Broom reads session transcripts: states arrive a few seconds late and it never sends a notification. Connecting adds hooks to the settings file after showing you the exact change."
    }
}
