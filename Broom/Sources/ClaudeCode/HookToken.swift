import Foundation

/// The bearer token that `broom-hook` must present: a random secret in a file only the user can read.
public enum HookToken {
    /// Returns the token stored at `url`, creating the file with a new random token if it is missing or empty.
    public static func loadOrCreate(at url: URL) throws -> String {
        let fileManager = FileManager.default
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            // Tighten the modes in case the file was copied or restored with a looser one.
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
            return existing
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        // The folder may already exist with the default mode, for example from the database; creating it again leaves that alone.
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        var generator = SystemRandomNumberGenerator()
        let token = (0..<32).map { _ in
            let hex = String(UInt8.random(in: .min ... .max, using: &generator), radix: 16)
            return (hex.count < 2 ? "0" : "") + hex
        }.joined()
        try? fileManager.removeItem(at: url)

        // `open` with the mode creates the file already private, so the secret is never readable by anyone else.
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        defer { close(descriptor) }
        let bytes = Array(token.utf8)
        guard write(descriptor, bytes, bytes.count) == bytes.count else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return token
    }

    /// Compares two tokens without stopping at the first difference.
    static func matches(_ candidate: String, _ token: String) -> Bool {
        let first = Array(candidate.utf8), second = Array(token.utf8)
        guard first.count == second.count else { return false }
        return zip(first, second).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
