import Foundation

/// Decides which session effects become notifications.
///
/// Only hook-reported changes produce effects, so an inferred state can never notify.
public struct NotificationPolicy: Sendable {
    /// Notify when a session starts waiting on the user. On by default.
    public var notifiesOnWaiting: Bool
    /// Notify when a session finishes. Off by default.
    public var notifiesOnDone: Bool

    /// At most one notification per session in this long.
    public static let minimumInterval: TimeInterval = 5 * 60
    /// The longest notification body, in characters.
    public static let maximumBodyLength = 180

    private var lastSentAt: [String: Date] = [:]

    /// Creates a policy with the given switches; no session has been notified yet.
    public init(notifiesOnWaiting: Bool = true, notifiesOnDone: Bool = false) {
        self.notifiesOnWaiting = notifiesOnWaiting
        self.notifiesOnDone = notifiesOnDone
    }

    /// Returns the notification to post for `effect`, or `nil` if it should not be posted.
    ///
    /// Posting is assumed when one is returned, so it counts toward the rate limit: asking again at once returns `nil`.
    public mutating func takeNotification(for effect: SessionEffect, session: LiveSession?, at now: Date) -> NotificationContent? {
        guard let session else { return nil }
        let kind: NotificationContent.Kind
        var failed = false
        switch effect {
        case .notifyWaiting:
            guard notifiesOnWaiting, session.state == .waiting, !session.isSnoozed(at: now) else { return nil }
            kind = .waiting
        case .notifyDone(_, let didFail):
            guard notifiesOnDone, session.state == .done else { return nil }
            kind = .done
            failed = didFail
        }
        if let last = lastSentAt[session.id], now.timeIntervalSince(last) < Self.minimumInterval {
            return nil
        }
        lastSentAt[session.id] = now

        let title = session.title.isEmpty ? (session.repoName ?? "Claude Code") : session.title
        let body = switch kind {
        case .waiting: session.waitingMessage ?? "Waiting for your input"
        case .done: failed ? "Stopped on an error" : "Finished"
        }
        return NotificationContent(sessionID: session.id, kind: kind, title: title, body: Self.truncated(body))
    }

    static func truncated(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard collapsed.count > maximumBodyLength else { return collapsed }
        return collapsed.prefix(maximumBodyLength - 1) + "…"
    }
}
