import Foundation

/// Pulls the words of a conversation out of a Claude Code transcript (`<session-id>.jsonl`) for the chat index.
///
/// It keeps what the user typed and what Claude wrote. Tool calls, tool output, subagent lines, slash-command
/// wrappers and interruption markers are left out. The line format is internal to Claude Code, so every lookup is
/// optional and anything unrecognised is skipped.
public enum TranscriptTextReader {
    /// Longer turns are cut to this many characters, which bounds the index without losing what a chat was about.
    public static let maximumTurnLength = 4000

    /// Reads the complete lines in `data`. A trailing partial line is left for the next read.
    public static func read(_ data: Data) -> TranscriptTextBatch {
        var batch = TranscriptTextBatch()
        var cursor = data.startIndex
        while let newline = data[cursor...].firstIndex(of: UInt8(ascii: "\n")) {
            // JSONSerialization returns autoreleased objects; without a pool a large file holds them all until the end.
            autoreleasepool {
                ingest(data[cursor..<newline], into: &batch)
            }
            cursor = data.index(after: newline)
        }
        batch.consumedByteCount = cursor - data.startIndex
        return batch
    }

    private static func ingest(_ line: Data, into batch: inout TranscriptTextBatch) {
        guard !line.isEmpty, let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        let type = entry["type"] as? String
        if type == "custom-title", let title = entry["customTitle"] as? String, !title.isEmpty {
            batch.customTitle = title
            return
        }
        guard type == "user" || type == "assistant", entry["isSidechain"] as? Bool != true, entry["isMeta"] as? Bool != true,
              let message = entry["message"] as? [String: Any]
        else { return }
        if let cwd = entry["cwd"] as? String, !cwd.isEmpty { batch.cwd = cwd }

        let text = text(of: message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConversation(text) else { return }
        batch.turns.append(ChatTurn(
            role: type == "user" ? .user : .assistant,
            text: String(text.prefix(maximumTurnLength)),
            date: (entry["timestamp"] as? String).flatMap(date(fromTimestamp:))
        ))
    }

    /// The message's own text: a plain string, or its text blocks joined. Tool blocks are skipped.
    private static func text(of message: [String: Any]) -> String {
        if let content = message["content"] as? String { return content }
        guard let blocks = message["content"] as? [[String: Any]] else { return "" }
        return blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    /// Whether `text` is something a person or Claude said, and not a marker Claude Code wrote into the transcript.
    static func isConversation(_ text: String) -> Bool {
        // Slash commands, command output and reminders are wrapped in tags; interruptions are bracketed; and a chat
        // that ran out of room carries on from a summary Claude Code writes as if the user had typed it.
        !text.isEmpty && !text.hasPrefix("<") && !text.hasPrefix("[Request interrupted") && !text.hasPrefix("Caveat:")
            && !text.hasPrefix(continuationPrefix)
    }

    private static let continuationPrefix = "This session is being continued from a previous conversation"

    private static func date(fromTimestamp string: String) -> Date? {
        try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
