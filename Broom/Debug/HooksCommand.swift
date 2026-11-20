import Foundation

/// `Broom --hooks <plan|connect|disconnect> --settings <file> [--yes]`: the installer from the command line.
///
/// The settings file must be named explicitly, so this never touches the real one by default. Without `--yes` it only prints the diff.
enum HooksCommand {
    static func run(arguments: [String], helperPath: String) -> Int32 {
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let action = value(after: "--hooks"), let settings = value(after: "--settings"),
              ["plan", "connect", "disconnect"].contains(action)
        else {
            print("usage: Broom --hooks <plan|connect|disconnect> --settings <file> [--yes]")
            return 64
        }

        let installer = HookInstaller(settingsURL: URL(fileURLWithPath: settings), helperPath: value(after: "--helper") ?? helperPath)
        do {
            let plan = try installer.plan(action == "disconnect" ? .disconnect : .connect)
            print("Settings file: \(installer.settingsURL.path)")
            print("Connected now: \(installer.isInstalled() ? "yes" : "no")")
            guard plan.hasChanges else {
                print("Nothing to change.")
                return 0
            }
            print(plan.diff.map(\.marked).joined(separator: "\n"))
            guard action != "plan", arguments.contains("--yes") else {
                print("\nNothing written. Add --yes to \(action == "plan" ? "connect" : action).")
                return 0
            }
            let backup = try installer.apply(plan)
            print("\nWritten. " + (backup.map { "Backup: \($0.path)" } ?? "No backup: the file did not exist."))
            return 0
        } catch {
            print("Failed, nothing written: \(error)")
            return 1
        }
    }
}
