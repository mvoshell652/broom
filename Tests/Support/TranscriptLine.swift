import Foundation

/// Builds transcript lines for tests, in the shape Claude Code writes them.
enum TranscriptLine {
    static func user(_ text: String, session: String, at seconds: TimeInterval = 0, isMeta: Bool = false) -> Data {
        line(["type": "user", "sessionId": session, "cwd": "/Users/dev/code/acme-api", "isSidechain": false, "isMeta": isMeta,
              "timestamp": timestamp(seconds), "message": ["role": "user", "content": text]])
    }

    static func assistant(_ text: String, session: String, at seconds: TimeInterval = 0, toolCommand: String? = nil) -> Data {
        var blocks: [[String: Any]] = [["type": "text", "text": text]]
        if let toolCommand {
            blocks.append(["type": "tool_use", "id": "tool-\(Int(seconds))", "name": "Bash", "input": ["command": toolCommand]])
        }
        return line(["type": "assistant", "sessionId": session, "isSidechain": false, "timestamp": timestamp(seconds),
                     "message": ["role": "assistant", "content": blocks]])
    }

    static func toolResult(_ output: String, session: String, at seconds: TimeInterval = 0) -> Data {
        line(["type": "user", "sessionId": session, "isSidechain": false, "timestamp": timestamp(seconds),
              "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "tool-\(Int(seconds))", "content": output]]]])
    }

    static func customTitle(_ title: String, session: String) -> Data {
        line(["type": "custom-title", "sessionId": session, "customTitle": title])
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        TestClock.at(seconds).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    private static func line(_ object: [String: Any]) -> Data {
        // Sorted keys keep the bytes the same from run to run.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).map { $0 + Data("\n".utf8) } ?? Data()
    }
}
