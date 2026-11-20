import Foundation
import Testing
@testable import BroomCore

@Suite("HookToken")
struct HookTokenTests {
    private let scratch: TemporaryDirectory
    private var directory: URL { scratch.url }
    private var file: URL { directory.appending(path: "nested/token") }

    init() throws {
        scratch = try TemporaryDirectory(prefix: "broom-support")
    }

    private func mode(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test("A missing token is created as 64 hex characters in a file only the user can read")
    func created() throws {
        let token = try HookToken.loadOrCreate(at: file)

        #expect(token.count == 64)
        #expect(token.allSatisfy { $0.isHexDigit })
        #expect(try mode(of: file) == 0o600)
        #expect(try mode(of: file.deletingLastPathComponent()) == 0o700)
        #expect(try String(contentsOf: file, encoding: .utf8) == token)
    }

    @Test("An existing token is reused, and a loose file mode is tightened")
    func reused() throws {
        let first = try HookToken.loadOrCreate(at: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        let second = try HookToken.loadOrCreate(at: file)

        #expect(second == first)
        #expect(try mode(of: file) == 0o600)
    }

    @Test("A folder that already exists with a looser mode is made private when the token is created or reused")
    func existingFolder() throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        _ = try HookToken.loadOrCreate(at: file)
        #expect(try mode(of: folder) == 0o700)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        _ = try HookToken.loadOrCreate(at: file)
        #expect(try mode(of: folder) == 0o700)
    }

    @Test("Two new tokens differ")
    func random() throws {
        let other = directory.appending(path: "other/token")

        let first = try HookToken.loadOrCreate(at: file)
        let second = try HookToken.loadOrCreate(at: other)

        #expect(first != second)
    }

    @Test("An empty token file is replaced")
    func emptyFile() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\n".utf8).write(to: file)

        #expect(try HookToken.loadOrCreate(at: file).count == 64)
        #expect(try mode(of: file) == 0o600)
    }

    @Test("Tokens match only when identical")
    func matching() {
        #expect(HookToken.matches("abc123", "abc123"))
        #expect(!HookToken.matches("abc124", "abc123"))
        #expect(!HookToken.matches("abc12", "abc123"))
        #expect(!HookToken.matches("", "abc123"))
    }
}
