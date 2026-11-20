/// What a notification says and which session it is about.
public struct NotificationContent: Equatable, Sendable {
    /// Why the notification is posted.
    public enum Kind: String, Sendable {
        case waiting
        case done
    }

    /// The session the notification is about, which Open and Snooze act on.
    public var sessionID: String
    public var kind: Kind
    /// The session's title, or its repo name when it has none.
    public var title: String
    /// The waiting message or a short summary of how the session finished, cut to `NotificationPolicy.maximumBodyLength`.
    public var body: String

    public init(sessionID: String, kind: Kind, title: String, body: String) {
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.body = body
    }
}
