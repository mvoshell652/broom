import Foundation
@testable import BroomCore

/// A throwaway projects directory laid out like `~/.claude/projects`, removed when the value is released.
final class TemporaryProjects: Sendable {
    let root: URL
    let project: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "broom-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        project = root.appending(path: "-Users-dev-code-acme-api")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `data` as the transcript of `sessionID` and returns its path.
    @discardableResult
    func write(_ data: Data, sessionID: String, modified: Date? = nil) throws -> String {
        try write(data, to: project.appending(path: "\(sessionID).jsonl"), modified: modified)
    }

    @discardableResult
    func write(_ data: Data, to url: URL, modified: Date? = nil) throws -> String {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url.path
    }

    /// Appends `data` to an existing file in place.
    func append(_ data: Data, toPath path: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
