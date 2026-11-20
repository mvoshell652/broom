import Foundation

/// Reads Claude Code transcripts into the chat index, picking up where it left off in each file.
public actor ChatIndexer {
    private let projectsDirectory: String
    private let store: ChatIndexStore
    private let embedder: (any SentenceEmbedder)?
    /// Whether every chat has been checked for a missing vector since launch. After that only changed chats are.
    private var hasCheckedAllVectors = false

    /// - Parameter embedder: Makes the vectors chats are compared by. `nil` indexes text only.
    public init(projectsDirectory: URL, store: ChatIndexStore, embedder: (any SentenceEmbedder)? = NaturalLanguageEmbedder()) {
        self.projectsDirectory = projectsDirectory.resolvingSymlinksInPath().path
        self.store = store
        self.embedder = embedder
    }

    /// Reads whatever is new in every session transcript, then computes vectors for chats that need one.
    @discardableResult
    public func indexAll() throws -> IndexSummary {
        var summary = IndexSummary()
        var changed: [String] = []
        let fileManager = FileManager.default
        // One query for every file's progress, so an unchanged file costs a stat and nothing else.
        let progress = try store.allProgress()
        for project in (try? fileManager.contentsOfDirectory(atPath: projectsDirectory)) ?? [] {
            let directory = projectsDirectory + "/" + project
            for name in (try? fileManager.contentsOfDirectory(atPath: directory)) ?? [] where name.hasSuffix(".jsonl") {
                try Task.checkCancellation()
                let path = directory + "/" + name
                guard case .session(let id) = TranscriptFile(path: path, projectsDirectory: projectsDirectory) else { continue }
                let (added, wasReset) = try index(path: path, chatID: id, progress: progress[path])
                if wasReset { summary.filesReset += 1 }
                if added > 0 {
                    changed.append(id)
                    summary.filesRead += 1
                    summary.turnsAdded += added
                }
            }
        }
        summary.chatsEmbedded = try embedPending(changed: changed)
        return summary
    }

    /// Reads the unread part of one transcript, given how far it had been read. Returns how many turns it added, and
    /// whether the file had been replaced or cut short, so its chat was dropped to be read again.
    private func index(
        path: String, chatID: String, progress: (fileNumber: UInt64, offset: UInt64)?
    ) throws -> (added: Int, wasReset: Bool) {
        // `stat`, not FileManager's attributes, which also read the file's extended attributes.
        var info = stat()
        guard stat(path, &info) == 0 else { return (0, false) }
        let size = UInt64(info.st_size)
        let fileNumber = UInt64(info.st_ino)

        var offset: UInt64 = 0
        var wasReset = false
        if let progress {
            if progress.fileNumber == fileNumber, progress.offset <= size {
                offset = progress.offset
            } else {
                // Replaced or truncated: what was indexed no longer describes the file.
                try store.removeChat(id: chatID)
                wasReset = true
            }
        }
        guard size > offset, let handle = FileHandle(forReadingAtPath: path) else { return (0, wasReset) }
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var chat = try store.chat(id: chatID) ?? IndexedChat(id: chatID, transcriptPath: path)
        chat.transcriptPath = path
        var added = 0
        var pending = Data()
        var reachedEnd = false
        while !reachedEnd {
            // Each chunk is autoreleased; drain it before the next, or a first index holds every file it read.
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
                    reachedEnd = true
                    return
                }
                pending.append(chunk)
                let batch = TranscriptTextReader.read(pending)
                guard batch.consumedByteCount > 0 else { return }
                pending.removeSubrange(pending.startIndex..<pending.startIndex + batch.consumedByteCount)
                offset += UInt64(batch.consumedByteCount)
                chat.merge(batch)
                added += batch.turns.count
                try store.save(chat, adding: batch.turns, fileNumber: fileNumber, offset: offset)
            }
        }
        return (added, wasReset)
    }

    /// Computes vectors for the chats that changed in this pass. The first pass after launch checks every chat, to
    /// pick up any that were indexed and never embedded; later passes do not, which keeps a quiet minute cheap.
    private func embedPending(changed: [String]) throws -> Int {
        guard let embedder else { return 0 }
        let candidates: [IndexedChat]
        if hasCheckedAllVectors {
            candidates = try changed.compactMap { try store.chat(id: $0) }
        } else {
            candidates = try store.chatsNeedingEmbedding()
            hasCheckedAllVectors = true
        }
        let sources = try store.embeddingSources(forChats: candidates.map(\.id))
        var count = 0
        for chat in candidates where !chat.embeddingText.isEmpty && sources[chat.id] != chat.embeddingText {
            try Task.checkCancellation()
            let text = chat.embeddingText
            guard let vector = embedder.vector(for: text) else { continue }
            try store.saveEmbedding(vector, of: text, forChat: chat.id)
            count += 1
        }
        return count
    }

    private static let chunkSize = 1 << 20
}
