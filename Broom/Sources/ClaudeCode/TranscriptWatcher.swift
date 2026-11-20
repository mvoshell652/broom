import Foundation

/// Watches Claude Code's transcripts and reports each session's parsed digest as its file grows.
///
/// Read-only: it never writes under the projects directory.
public actor TranscriptWatcher: SessionSource {
    /// Transcripts are Claude Code's.
    public nonisolated let kind = SessionSourceKind.claudeCode

    /// Transcripts untouched for longer than this are not read at launch; such sessions would be hidden anyway.
    public static let launchWindow: TimeInterval = StateMachine.retention

    private let projectsDirectory: String
    private let now: @Sendable () -> Date
    private var tracked: [String: TrackedFile] = [:]
    /// Transcripts outside the projects directory that a hook named, by path. They are polled, not watched.
    private var external: [String: String] = [:]

    /// How often transcripts outside the projects directory are checked for new lines.
    public static let externalPollInterval: Duration = .seconds(5)

    /// How long to wait before watching again when the directory stream ended without the directory appearing.
    static let resubscribeDelay: Duration = .seconds(5)

    /// Read progress for one transcript.
    private struct TrackedFile {
        var parser = TranscriptParser()
        /// Bytes handed to the parser so far.
        var offset: UInt64 = 0
        /// The file's inode, to notice when it is replaced.
        var fileNumber: UInt64 = 0
    }

    public init(projectsDirectory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.projectsDirectory = projectsDirectory.resolvingSymlinksInPath().path
        self.now = now
    }

    public nonisolated func events() -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    var directoryAppeared = false
                    // Until the projects directory exists (Claude Code has never run), watch the closest folder that does.
                    let watched = Self.nearestExistingDirectory(to: projectsDirectory)
                    // Subscribe before scanning so a write that lands during the scan is not missed.
                    let changes = DirectoryEvents.stream(for: URL(fileURLWithPath: watched))
                    for event in await scanAll() {
                        continuation.yield(event)
                    }
                    for await batch in changes {
                        if watched != projectsDirectory, FileManager.default.fileExists(atPath: projectsDirectory) {
                            // The directory appeared: start over, watching it directly.
                            directoryAppeared = true
                            break
                        }
                        let events = batch.needsRescan ? await scanAll() : await scan(paths: batch.paths)
                        for event in events {
                            continuation.yield(event)
                        }
                    }
                    // The stream also ends when it could not be created. Without a pause that would loop at full speed.
                    if !directoryAppeared {
                        do { try await Task.sleep(for: Self.resubscribeDelay) } catch { break }
                    }
                }
                continuation.finish()
            }
            let poller = Task {
                while !Task.isCancelled {
                    // Leave on cancellation instead of scanning once more.
                    do { try await Task.sleep(for: Self.externalPollInterval) } catch { break }
                    for event in await scanExternal() {
                        continuation.yield(event)
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                poller.cancel()
            }
        }
    }

    /// Tells the watcher where a hook said a session's transcript is.
    ///
    /// A path under the projects directory is already watched. Any other, for example when Claude Code runs
    /// with a different `CLAUDE_CONFIG_DIR` than Broom, is read now and then checked on an interval.
    ///
    /// Returns the event for what the first read found, for the caller to apply. It is returned rather than sent on
    /// the event stream because the stream may not be running yet, and the bytes read here are not read again.
    @discardableResult
    public func register(sessionID: String, transcriptPath: String) -> SessionEvent? {
        let path = Self.resolved(transcriptPath)
        guard path.hasSuffix(".jsonl"), TranscriptFile(path: path, projectsDirectory: projectsDirectory) == nil,
              external.updateValue(sessionID, forKey: path) == nil
        else { return nil }
        return readExternal(path: path, sessionID: sessionID)
    }

    /// Reads what is new in every registered outside transcript.
    public func scanExternal() -> [SessionEvent] {
        external.compactMap { path, sessionID in readExternal(path: path, sessionID: sessionID) }
    }

    private func readExternal(path: String, sessionID: String) -> SessionEvent? {
        readNewBytes(atPath: path).map { digest in
            SessionEvent(sessionID: sessionID, date: now(), signal: .transcriptActivity(digest), transcriptPath: path)
        }
    }

    /// Reads what is new in every session transcript modified within the launch window and returns one event per changed session.
    public func scanAll() -> [SessionEvent] {
        let fileManager = FileManager.default
        let cutoff = now().addingTimeInterval(-Self.launchWindow)
        var paths: [String] = []

        for project in (try? fileManager.contentsOfDirectory(atPath: projectsDirectory)) ?? [] {
            let directory = projectsDirectory + "/" + project
            for name in (try? fileManager.contentsOfDirectory(atPath: directory)) ?? [] where name.hasSuffix(".jsonl") {
                let path = directory + "/" + name
                guard let modified = Self.attributes(atPath: path)?.modified, modified >= cutoff else { continue }
                paths.append(path)
            }
        }
        return scan(paths: paths)
    }

    /// Reads whatever is new in the given files and returns the resulting events. Paths that are not transcripts are ignored.
    public func scan(paths: [String]) -> [SessionEvent] {
        var events: [SessionEvent] = []
        var seen = Set<String>()

        for path in paths.map(Self.resolved) where seen.insert(path).inserted {
            switch TranscriptFile(path: path, projectsDirectory: projectsDirectory) {
            case .session(let id):
                if let digest = readNewBytes(atPath: path) {
                    events.append(SessionEvent(
                        sessionID: id, date: now(), signal: .transcriptActivity(digest), transcriptPath: path
                    ))
                }
            case .subagent(let parentSessionID):
                if let modified = Self.attributes(atPath: path)?.modified {
                    events.append(SessionEvent(
                        sessionID: parentSessionID, date: now(), signal: .subagentTranscriptActivity(modified)
                    ))
                }
            case nil:
                break
            }
        }
        return events
    }

    // MARK: - Reading

    /// Feeds the file's unread bytes to its parser. Returns the digest if anything new was read and the transcript has a conversation.
    private func readNewBytes(atPath path: String) -> TranscriptDigest? {
        guard let attributes = Self.attributes(atPath: path) else {
            tracked[path] = nil
            return nil
        }
        var file = tracked[path] ?? TrackedFile(fileNumber: attributes.fileNumber)
        if file.fileNumber != attributes.fileNumber || attributes.size < file.offset {
            // Replaced or truncated: what was parsed no longer describes the file.
            file = TrackedFile(fileNumber: attributes.fileNumber)
        }
        guard attributes.size > file.offset, let handle = FileHandle(forReadingAtPath: path) else {
            tracked[path] = file
            return nil
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: file.offset)
            var reachedEnd = false
            while !reachedEnd {
                // Each chunk is autoreleased; drain it before reading the next, or a launch scan holds every file it read.
                try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
                        reachedEnd = true
                        return
                    }
                    file.parser.consume(chunk)
                    file.offset += UInt64(chunk.count)
                }
            }
        } catch {
            // Keep what was read; the next change notification picks up from `offset`.
        }
        tracked[path] = file
        return file.parser.digest.startedAt == nil ? nil : file.parser.digest
    }

    private static let chunkSize = 1 << 20

    private static func attributes(atPath path: String) -> (size: UInt64, modified: Date, fileNumber: UInt64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? UInt64,
              let modified = attributes[.modificationDate] as? Date,
              let fileNumber = attributes[.systemFileNumber] as? UInt64
        else { return nil }
        return (size, modified, fileNumber)
    }

    private static func nearestExistingDirectory(to path: String) -> String {
        var url = URL(fileURLWithPath: path)
        while url.path != "/", !FileManager.default.fileExists(atPath: url.path) {
            url.deleteLastPathComponent()
        }
        return url.path
    }

    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
