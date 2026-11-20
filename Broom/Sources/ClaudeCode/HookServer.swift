import BroomShared
import Foundation
import Network
import os

/// Receives hook events from `broom-hook` on the loopback interface and reports them as session events.
///
/// It listens on 127.0.0.1 only and answers nothing without the bearer token.
public final class HookServer: SessionSource {
    /// Hooks come from Claude Code.
    public let kind = SessionSourceKind.claudeCode

    private let port: UInt16
    private let token: String
    private let now: @Sendable () -> Date
    private let record: (@Sendable (HookPayload, Date) async -> Void)?
    private let queue = DispatchQueue(label: "app.broom.hook-server")
    private let log = Logger(subsystem: "app.broom", category: "hooks")

    /// How long a connection may take to send its request.
    static let connectionTimeout: TimeInterval = 2
    /// How far a helper's own timestamp may differ from the server's clock and still be used.
    static let acceptedClockDifference: TimeInterval = 5

    /// Creates a server for `port` (0 picks a free one). `record` is called with every accepted payload, for the event log.
    public init(
        port: UInt16 = HookEndpoint.defaultPort,
        token: String,
        now: @escaping @Sendable () -> Date = { Date() },
        record: (@Sendable (HookPayload, Date) async -> Void)? = nil
    ) {
        self.port = port
        self.token = token
        self.now = now
        self.record = record
    }

    /// Starts listening on the configured port. Call once; see `events(onReady:)`.
    public func events() -> AsyncStream<SessionEvent> {
        events(onReady: { _ in })
    }

    /// Starts listening. `onReady` is called with the port once the server accepts connections.
    ///
    /// If the port cannot be bound (another Broom is running), the stream ends and transcripts remain the only signal.
    public func events(onReady: @escaping @Sendable (UInt16) -> Void) -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
            guard let listener = try? NWListener(using: parameters) else {
                log.error("Could not create the hook listener on port \(self.port)")
                continuation.finish()
                return
            }

            listener.stateUpdateHandler = { [log, weak listener] state in
                switch state {
                case .ready:
                    if let port = listener?.port?.rawValue { onReady(port) }
                case .failed(let error):
                    log.error("Hook listener failed: \(error)")
                    listener?.cancel()
                    continuation.finish()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                serve(connection, continuation: continuation)
            }
            continuation.onTermination = { _ in listener.cancel() }
            listener.start(queue: queue)
        }
    }

    // MARK: - Connections

    private func serve(_ connection: NWConnection, continuation: AsyncStream<SessionEvent>.Continuation) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { connection.cancel() }
        receive(on: connection, buffered: Data(), continuation: continuation)
    }

    private func receive(on connection: NWConnection, buffered: Data, continuation: AsyncStream<SessionEvent>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            var buffered = buffered
            if let data { buffered.append(data) }

            switch HTTPRequest.parse(buffered, authorize: authorize) {
            case .complete(let request):
                respond(status: handle(request, continuation: continuation), on: connection)
            case .rejected(let status):
                respond(status: status, on: connection)
            case .needsMoreData:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive(on: connection, buffered: buffered, continuation: continuation)
                }
            }
        }
    }

    /// Checks a request's path, method and token from its headers. Returns the status to refuse it with, or `nil` to accept.
    private func authorize(method: String, path: String, headers: [String: String]) -> Int? {
        guard path == HookEndpoint.path else { return 404 }
        guard method == "POST" else { return 405 }
        guard let authorization = headers["authorization"], authorization.hasPrefix("Bearer "),
              HookToken.matches(String(authorization.dropFirst("Bearer ".count)), token)
        else { return 401 }
        return nil
    }

    /// Accepts one authorised request. Returns the HTTP status to answer with.
    private func handle(_ request: HTTPRequest, continuation: AsyncStream<SessionEvent>.Continuation) -> Int {
        guard let payload = try? JSONDecoder().decode(HookPayload.self, from: request.body) else { return 400 }

        let date = payload.receivedDate(serverTime: now(), acceptedDifference: Self.acceptedClockDifference)
        if let event = payload.sessionEvent(receivedAt: date) {
            continuation.yield(event)
        }
        if let record {
            Task { await record(payload, date) }
        }
        return 204
    }

    private func respond(status: Int, on connection: NWConnection) {
        let reason = [204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed",
                      413: "Payload Too Large", 431: "Request Header Fields Too Large", 501: "Not Implemented"][status] ?? "Error"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
