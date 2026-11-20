import SwiftUI

/// Shows exactly what would change in `settings.json` and asks before writing it.
struct HookChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: HookInstaller.Plan
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plan.change == .connect ? "Connect Claude Code" : "Disconnect Claude Code")
                .font(.headline)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(plan.diff) { line in
                        Text(line.marked)
                            .font(.callout.monospaced())
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(accessibilityLabel(for: line))
                    }
                }
                .padding(8)
                .textSelection(.enabled)
            }
            .frame(minHeight: 220)
            .background(.background.secondary, in: .rect(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.change == .connect ? "Write changes" : "Remove hooks") {
                    model.apply(plan)
                    dismiss()
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!plan.hasChanges)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
    }

    private var settingsPath: String { model.installer.settingsURL.path }

    private var summary: String {
        guard plan.hasChanges else { return "\(settingsPath) already has no changes to make." }
        let backup = plan.currentText == nil ? "The file does not exist yet and will be created." : "A backup is saved next to it first."
        // Removed lines in a connect mean the file's layout could not be kept exactly.
        let reformats = plan.change == .connect && plan.diff.contains { $0.kind == .removed }
        switch plan.change {
        case .connect where reformats:
            return "Hooks will be added to \(settingsPath), and some lines will be re-laid-out without changing what they say. Your other hooks are left as they are. \(backup)"
        case .connect: return "These lines will be added to \(settingsPath). Your other hooks are left as they are. \(backup)"
        case .disconnect: return "These lines will be removed from \(settingsPath). Only Broom's entries are touched. \(backup)"
        }
    }

    private func color(for kind: DiffLine.Kind) -> AnyShapeStyle {
        switch kind {
        case .added: AnyShapeStyle(BroomStyle.doneOnGray)
        case .removed: AnyShapeStyle(BroomStyle.waitingTextOnGray)
        case .unchanged: AnyShapeStyle(.primary)
        case .gap: AnyShapeStyle(.secondary)
        }
    }

    private func accessibilityLabel(for line: DiffLine) -> String {
        switch line.kind {
        case .added: "Added: \(line.text)"
        case .removed: "Removed: \(line.text)"
        case .unchanged: line.text
        case .gap: "Unchanged lines not shown"
        }
    }
}
