import Foundation
@testable import Broom

/// A long-running process that Broom recognises as Claude Code, for tests that list or signal processes.
///
/// It is this package's own `Broom` binary, copied under the name `claude` and run in `--watch` mode on an
/// empty folder. A copy of a system tool such as `/bin/sleep` cannot be used: macOS kills system binaries
/// that are run from another location.
final class StandInClaude {
    let process = Process()
    let directory: URL

    var pid: Int32 { process.processIdentifier }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "broom-standin-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory.appending(path: "projects"), withIntermediateDirectories: true)
        let executable = directory.appending(path: "claude")
        try FileManager.default.copyItem(at: Self.broomBinary, to: executable)

        process.executableURL = executable
        process.arguments = ["--watch"]
        process.currentDirectoryURL = directory
        process.environment = [
            "BROOM_PROJECTS_DIR": directory.appending(path: "projects").path,
            "BROOM_SUPPORT_DIR": directory.appending(path: "support").path,
            "BROOM_DATABASE": ":memory:",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    deinit {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Waits until the child has exec'd and shows up as Claude Code, which is when it can be listed or signalled.
    func waitUntilRecognised() async -> Bool {
        await eventually { StopSession.isRunning(pid) }
    }

    /// The `Broom` executable built alongside the tests.
    private static var broomBinary: URL {
        var folder = Bundle.module.bundleURL
        while folder.path != "/" {
            folder.deleteLastPathComponent()
            let candidate = folder.appending(path: "Broom")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return folder.appending(path: "Broom")
    }
}
