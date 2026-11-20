import Foundation

/// A signal for one session at one moment.
public struct SessionEvent: Sendable, Equatable {
    /// The Claude Code session this is about.
    public var sessionID: String
    /// When the signal happened, not when it was processed.
    public var date: Date
    public var signal: SessionSignal
    /// The session's working directory, when the signal carries it.
    public var cwd: String?
    /// The session's transcript file, when the signal carries it.
    public var transcriptPath: String?
    /// The session's Claude Code process, when a hook reported it.
    public var processID: Int32?

    public init(
        sessionID: String,
        date: Date,
        signal: SessionSignal,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        processID: Int32? = nil
    ) {
        self.sessionID = sessionID
        self.date = date
        self.signal = signal
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.processID = processID
    }
}
