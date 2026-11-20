import Darwin
import Foundation
@testable import BroomCore

/// Helpers for exercising the hook server and the `broom-hook` binary without touching the real port or token.
enum HookTestSupport {
    /// The `broom-hook` executable built alongside the tests.
    static var helperURL: URL {
        // The resource bundle sits inside the test bundle; the helper is in the products folder above it.
        var folder = Bundle.module.bundleURL
        while folder.path != "/" {
            folder.deleteLastPathComponent()
            let candidate = folder.appending(path: "broom-hook")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return folder.appending(path: "broom-hook")
    }

    /// Starts `server` on a free port and returns that port with the event stream.
    static func start(_ server: HookServer) async -> (port: UInt16, events: AsyncStream<SessionEvent>)? {
        let (ports, portContinuation) = AsyncStream<UInt16>.makeStream()
        let events = server.events(onReady: { port in
            portContinuation.yield(port)
            portContinuation.finish()
        })
        var iterator = ports.makeAsyncIterator()
        guard let port = await iterator.next() else { return nil }
        return (port, events)
    }

    /// Sends raw bytes to the loopback port and returns the HTTP status of the reply, or `nil` if there was none.
    static func send(_ request: Data, toPort port: UInt16) async -> Int? {
        await Task.detached {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connected == 0 else { return nil }
            _ = request.withUnsafeBytes { write(descriptor, $0.baseAddress, request.count) }

            var reply = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = read(descriptor, &buffer, buffer.count)
                guard count > 0 else { break }
                reply.append(contentsOf: buffer[0..<count])
            }
            let line = String(decoding: reply.prefix(32), as: UTF8.self).split(separator: " ")
            return line.count > 1 ? Int(line[1]) : nil
        }.value
    }

    /// Whether something accepts connections on the loopback `port` right now.
    static func isListening(onPort port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Builds a POST to the hook endpoint with exactly these header lines in place of the usual `Authorization` line.
    static func post(_ body: String, headerLines: [String]) -> Data {
        var head = "POST /v1/events HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
        for line in headerLines { head += line + "\r\n" }
        head += "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        return Data((head + body).utf8)
    }

    /// Builds a POST to the hook endpoint.
    static func post(_ body: String, token: String?, path: String = "/v1/events", method: String = "POST") -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
        if let token { head += "Authorization: Bearer \(token)\r\n" }
        head += "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        return Data((head + body).utf8)
    }

    /// The result of one `broom-hook` run.
    struct HelperRun {
        var exitCode: Int32
        var stdout: Data
        var stderr: Data
        var duration: TimeInterval
    }

    /// Runs `broom-hook` with `input` on stdin, pointed at `port` and at the token in `supportDirectory`.
    static func runHelper(input: Data, port: UInt16, supportDirectory: URL) throws -> HelperRun {
        let process = Process()
        process.executableURL = helperURL
        process.environment = ["BROOM_HOOK_PORT": String(port), "BROOM_SUPPORT_DIR": supportDirectory.path]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let start = Date()
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let duration = Date().timeIntervalSince(start)

        return HelperRun(
            exitCode: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
            duration: duration
        )
    }

    /// A throwaway folder, with a token file in it when `token` is given.
    static func supportDirectory(token: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "broom-support-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let token {
            try Data(token.utf8).write(to: directory.appending(path: "token"))
        }
        return directory
    }
}
