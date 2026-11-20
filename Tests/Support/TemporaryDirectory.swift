import Foundation

/// A throwaway folder that is removed when the value is released, so a suite that holds one as a stored property cleans up after every test.
final class TemporaryDirectory: Sendable {
    let url: URL

    init(prefix: String = "broom-tests") throws {
        url = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
