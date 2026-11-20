import Foundation

/// The fields Broom reads from a Claude Code hook's stdin JSON. Everything else is ignored.
public struct HookPayload: Decodable, Equatable, Sendable {
    /// Claude Code's `session_id`.
    public var sessionID: String
    /// Claude Code's `hook_event_name`, such as `PreToolUse`.
    public var eventName: String
    public var cwd: String?
    public var transcriptPath: String?
    /// Set only when the hook fired inside a subagent.
    public var agentID: String?
    /// What started the session, on `SessionStart`: startup, resume, clear or compact.
    public var source: String?
    /// The session's title, when Claude Code reports one.
    public var sessionTitle: String?
    /// The user's prompt, on `UserPromptSubmit`. Used for the title and never stored.
    public var prompt: String?
    /// The tool involved, on tool events.
    public var toolName: String?
    /// What a `Notification` hook is about, such as a permission request.
    public var notificationType: String?
    /// The text of a `Notification` hook.
    public var message: String?
    /// The error that ended a turn, on `StopFailure`.
    public var error: String?
    /// The Claude Code process, added by `broom-hook` when it can find it.
    public var pid: Int32?
    /// When `broom-hook` ran, added by it, as an ISO 8601 string.
    public var receivedAt: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case eventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case agentID = "agent_id"
        case source
        case sessionTitle = "session_title"
        case prompt
        case toolName = "tool_name"
        case notificationType = "notification_type"
        case message
        case error
        case pid
        case receivedAt = "received_at"
    }

    /// The state-machine event for this payload, or `nil` for hook events Broom does not track.
    public func sessionEvent(receivedAt date: Date) -> SessionEvent? {
        guard let signal else { return nil }
        return SessionEvent(
            sessionID: sessionID, date: date, signal: signal, cwd: cwd, transcriptPath: transcriptPath, processID: pid
        )
    }

    /// The time to stamp this event with: the helper's own timestamp when it is close to `serverTime`, otherwise `serverTime`.
    ///
    /// Each hook runs in its own process, so the helper's time orders events better than arrival does.
    public func receivedDate(serverTime: Date, acceptedDifference: TimeInterval) -> Date {
        guard let receivedAt,
              let date = try? Date(receivedAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
              abs(date.timeIntervalSince(serverTime)) <= acceptedDifference
        else { return serverTime }
        return date
    }

    private var signal: SessionSignal? {
        if let agentID, !agentID.isEmpty {
            return .subagentActivity
        }
        switch eventName {
        case "SessionStart":
            return .sessionStarted(source: source.flatMap(SessionStartSource.init(rawValue:)) ?? .startup, title: sessionTitle)
        case "UserPromptSubmit":
            return .promptSubmitted(prompt: prompt, title: sessionTitle)
        case "PreToolUse":
            return .toolActivity(.started)
        case "PostToolUse":
            return .toolActivity(.finished)
        case "PostToolUseFailure":
            return .toolActivity(.failed)
        case "PermissionRequest":
            return .permissionRequested(toolName: toolName)
        case "Notification":
            return .notification(NotificationKind(notificationType: notificationType), message: message)
        case "Stop":
            return .stopped
        case "StopFailure":
            return .stopFailed(error: error)
        case "SessionEnd":
            return .sessionEnded
        default:
            return nil
        }
    }
}
