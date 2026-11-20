/// What a `Notification` hook means for session state.
public enum NotificationKind: Sendable, Equatable {
    /// Claude is blocked on the user: a permission prompt, an elicitation dialog, or an agent that needs input.
    case needsUser
    /// Claude has been idle at the prompt for a while.
    case idlePrompt
    /// Everything else. Never changes state.
    case informational

    /// Classifies a hook payload's `notification_type`. A missing or unknown type is informational.
    public init(notificationType: String?) {
        switch notificationType {
        case "permission_prompt", "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog":
            self = .needsUser
        case "idle_prompt":
            self = .idlePrompt
        default:
            self = .informational
        }
    }
}
