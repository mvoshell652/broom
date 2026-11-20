/// Something the app should do because of a state change.
public enum SessionEffect: Sendable, Equatable {
    /// Post the "waiting on you" notification for this session. Only ever produced by hook signals.
    case notifyWaiting(sessionID: String)
    /// A hook reported that the session's turn finished, normally or on an API error. The app notifies only if the user turned that on.
    case notifyDone(sessionID: String, failed: Bool)
}
