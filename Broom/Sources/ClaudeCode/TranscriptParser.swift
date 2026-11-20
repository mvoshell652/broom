import Foundation

/// Incrementally parses a Claude Code session transcript (`<session-id>.jsonl`) into a `TranscriptDigest`.
///
/// Feed it bytes as the file grows. The line format is internal to Claude Code, so every lookup is
/// optional: unknown line types are ignored and malformed lines are counted and skipped.
public struct TranscriptParser: Sendable {
    /// Everything parsed so far.
    public private(set) var digest = TranscriptDigest()
    /// Bytes consumed through the last complete line. Resume reading the file from this offset.
    public private(set) var consumedByteCount = 0

    private var partialLine = Data()
    /// Main-agent tool calls with no result yet, oldest first.
    private var pendingToolUses: [(id: String, name: String)] = []
    private var todoProgress: StepProgress?
    private var taskStatuses: [String: String] = [:]
    /// Tool-use ids of `TaskCreate` calls whose result, and so task id, has not arrived yet.
    private var unresolvedTaskCreates: [String] = []
    private var progressComesFromTasks = false

    public init() {}

    /// Parses the next bytes of the file. A trailing partial line is kept until its newline arrives.
    public mutating func consume(_ chunk: Data) {
        partialLine.append(chunk)
        var cursor = partialLine.startIndex
        while let newline = partialLine[cursor...].firstIndex(of: UInt8(ascii: "\n")) {
            // JSONSerialization hands back autoreleased objects. Without a pool per line they pile up
            // until the whole scan ends, which made launch use several times the size of the transcripts.
            autoreleasepool {
                ingest(partialLine[cursor..<newline])
            }
            cursor = partialLine.index(after: newline)
        }
        consumedByteCount += cursor - partialLine.startIndex
        // One removal per chunk; removing per line would shift the whole buffer every time.
        partialLine.removeSubrange(partialLine.startIndex..<cursor)
    }

    /// Forgets everything, for when the file was truncated or replaced.
    public mutating func reset() {
        self = TranscriptParser()
    }

    // MARK: - Lines

    private mutating func ingest(_ line: Data) {
        guard line.contains(where: { !Self.isWhitespace($0) }) else { return }
        guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            digest.malformedLineCount += 1
            return
        }
        if digest.sessionID == nil, let sessionID = entry["sessionId"] as? String {
            digest.sessionID = sessionID
        }
        if let timestamp = (entry["timestamp"] as? String).flatMap(Self.date(fromTimestamp:)) {
            digest.lastActivityAt = max(digest.lastActivityAt ?? timestamp, timestamp)
        }

        switch entry["type"] as? String {
        case "user":
            ingestConversationLine(entry, isUser: true)
        case "assistant":
            ingestConversationLine(entry, isUser: false)
        case "custom-title":
            if let title = entry["customTitle"] as? String, !title.isEmpty {
                digest.customTitle = title
            }
        case "summary":
            // Older transcripts only. A custom title wins when both exist.
            if digest.customTitle == nil, let summary = entry["summary"] as? String, !summary.isEmpty {
                digest.customTitle = summary
            }
        default:
            // Metadata (`api-request-blob`, `last-prompt`, `queue-operation`, ...) and types added later.
            break
        }
    }

    private mutating func ingestConversationLine(_ entry: [String: Any], isUser: Bool) {
        // Subagent lines count toward liveness and nothing else.
        guard entry["isSidechain"] as? Bool != true else { return }

        if digest.startedAt == nil, let timestamp = (entry["timestamp"] as? String).flatMap(Self.date(fromTimestamp:)) {
            digest.startedAt = timestamp
        }
        if let cwd = entry["cwd"] as? String, !cwd.isEmpty {
            digest.cwd = cwd
        }
        guard let message = entry["message"] as? [String: Any] else { return }

        if isUser {
            ingestUserMessage(message, entry: entry)
        } else {
            ingestAssistantMessage(message)
        }
    }

    private mutating func ingestUserMessage(_ message: [String: Any], entry: [String: Any]) {
        var text = ""
        var hasToolResult = false

        if let content = message["content"] as? String {
            text = content
        } else if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                switch block["type"] as? String {
                case "text":
                    text += block["text"] as? String ?? ""
                case "tool_result":
                    hasToolResult = true
                    ingestToolResult(block, entry: entry)
                default:
                    break
                }
            }
        }

        if hasToolResult {
            digest.tail = pendingToolUses.last.map { .pendingTool(name: $0.name) } ?? .other
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[Request interrupted") {
            pendingToolUses.removeAll()
            digest.tail = .interrupted
            digest.interruptedAt = (entry["timestamp"] as? String).flatMap(Self.date(fromTimestamp:)) ?? digest.lastActivityAt
            return
        }
        guard entry["isMeta"] as? Bool != true, Self.isPrompt(text) else { return }
        // A new prompt means any tool call still without a result was abandoned.
        pendingToolUses.removeAll()
        digest.counts.userTurns += 1
        if digest.firstPrompt == nil {
            digest.firstPrompt = text
        }
        digest.tail = .other
    }

    private mutating func ingestAssistantMessage(_ message: [String: Any]) {
        guard let blocks = message["content"] as? [[String: Any]] else { return }
        var lastText: String?

        for block in blocks {
            switch block["type"] as? String {
            case "text":
                lastText = block["text"] as? String
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                digest.counts.toolCalls += 1
                pendingToolUses.append((id, name))
                ingestProgressToolUse(name: name, id: id, input: block["input"] as? [String: Any] ?? [:])
            default:
                break
            }
        }

        if let pending = pendingToolUses.last {
            digest.tail = .pendingTool(name: pending.name)
        } else if let question = lastText.flatMap(Self.trailingQuestion(in:)) {
            digest.tail = .assistantQuestion(question)
        } else if lastText != nil {
            digest.tail = .other
        }
    }

    private mutating func ingestToolResult(_ block: [String: Any], entry: [String: Any]) {
        guard let toolUseID = block["tool_use_id"] as? String else { return }
        pendingToolUses.removeAll { $0.id == toolUseID }

        guard let position = unresolvedTaskCreates.firstIndex(of: toolUseID) else { return }
        unresolvedTaskCreates.remove(at: position)
        if block["is_error"] as? Bool != true {
            // Without an id in the result, fall back to the next sequential one.
            let taskID = Self.createdTaskID(in: block, entry: entry) ?? String(taskStatuses.count + 1)
            taskStatuses[taskID] = taskStatuses[taskID] ?? "pending"
        }
        refreshProgress()
    }

    // MARK: - Progress

    private mutating func ingestProgressToolUse(name: String, id: String, input: [String: Any]) {
        switch name {
        case "TodoWrite":
            guard let todos = input["todos"] as? [[String: Any]] else { return }
            let completed = todos.count { $0["status"] as? String == "completed" }
            todoProgress = StepProgress(completed: completed, total: todos.count)
            progressComesFromTasks = false
        case "TaskCreate":
            // The task's id arrives with the tool result; until then it counts as one pending task.
            unresolvedTaskCreates.append(id)
            progressComesFromTasks = true
        case "TaskUpdate":
            progressComesFromTasks = true
            guard let taskID = Self.string(in: input, forAnyOf: ["taskId", "id", "task_id"]),
                  taskStatuses[taskID] != nil,
                  let status = input["status"] as? String
            else { return }
            taskStatuses[taskID] = status == "deleted" ? nil : status
        default:
            return
        }
        refreshProgress()
    }

    private mutating func refreshProgress() {
        let progress = progressComesFromTasks
            ? StepProgress(
                completed: taskStatuses.values.count { $0 == "completed" },
                total: taskStatuses.count + unresolvedTaskCreates.count
            )
            : todoProgress
        digest.progress = progress.flatMap { $0.total > 0 ? $0 : nil }
    }

    /// Finds the id of the task a `TaskCreate` call made, from its structured result or its result text.
    private static func createdTaskID(in block: [String: Any], entry: [String: Any]) -> String? {
        if let result = entry["toolUseResult"] as? [String: Any] {
            if let task = result["task"] as? [String: Any], let id = string(in: task, forAnyOf: ["id", "taskId"]) {
                return id
            }
            if let id = string(in: result, forAnyOf: ["taskId", "id"]) {
                return id
            }
        }
        var text = block["content"] as? String ?? ""
        if let parts = block["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        return text.firstMatch(of: /#(\d+)/).map { String($0.1) }
    }

    // MARK: - Helpers

    private static func string(in dictionary: [String: Any], forAnyOf keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
            if let value = dictionary[key] as? Int { return String(value) }
        }
        return nil
    }

    /// Whether user text is something the user typed, not harness output recorded as a user line.
    private static func isPrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.hasPrefix("<local-command-") && !trimmed.hasPrefix("[Request interrupted")
    }

    /// Returns `text` trimmed and capped if it ends with a question mark.
    private static func trailingQuestion(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return nil }
        return trimmed.count > maximumQuestionLength ? "…" + trimmed.suffix(maximumQuestionLength - 1) : trimmed
    }

    private static let maximumQuestionLength = 200

    private static func date(fromTimestamp string: String) -> Date? {
        (try? Date(string, strategy: fractionalTimestamp)) ?? (try? Date(string, strategy: wholeTimestamp))
    }

    private static let fractionalTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeTimestamp = Date.ISO8601FormatStyle()

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }
}
