import Foundation

extension LiveSession {
    /// When a finished session finished. An ended session's state change is when it ended, so its last activity is used.
    public var finishedAt: Date {
        state == .ended ? lastActivityAt : stateChangedAt
    }
}
