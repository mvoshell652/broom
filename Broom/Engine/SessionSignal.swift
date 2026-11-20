import Foundation

/// One input to the state machine.
public enum SessionSignal: Sendable, Equatable {
    /// `SessionStart` hook.
    case sessionStarted(source: SessionStartSource, title: String?)
    /// `UserPromptSubmit` hook.
    case promptSubmitted(prompt: String?, title: String?)
    /// `PreToolUse`, `PostToolUse` or `PostToolUseFailure` hook from the main agent.
    case toolActivity(ToolActivityPhase)
    /// `PermissionRequest` hook.
    case permissionRequested(toolName: String?)
    /// `Notification` hook.
    case notification(NotificationKind, message: String?)
    /// `Stop` hook.
    case stopped
    /// `StopFailure` hook.
    case stopFailed(error: String?)
    /// `SessionEnd` hook.
    case sessionEnded
    /// Any hook that fired inside a subagent.
    case subagentActivity
    /// The transcript was read; carries everything parsed from it so far.
    case transcriptActivity(TranscriptDigest)
    /// Broom interrupted the session's process because the user asked it to stop.
    case interruptedByUser
    /// A subagent's transcript was written to at the given time.
    case subagentTranscriptActivity(Date)
    /// A periodic check, carrying the session's process if one is alive.
    case tick(processID: Int32?)

    /// Whether the signal came from a Claude Code hook.
    public var isHookSignal: Bool {
        switch self {
        case .transcriptActivity, .subagentTranscriptActivity, .tick, .interruptedByUser: false
        default: true
        }
    }
}
